# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# Builds standalone ESP and root partition images for initrd-based flashing.
# These replace the legacy sdImage approach: instead of a single disk image,
# we build ESP (FAT32) and root (ext4) as independent compressed images that
# are written to eMMC partitions created on-device by sgdisk.
#
{
  config,
  pkgs,
  modulesPath,
  options,
  lib,
  ...
}:
let
  cfg = config.ghaf.hardware.nvidia.orin;
  jetpackCfg = config.hardware.nvidia-jetpack;

  # External-automation manifest. Emitted as flash-manifest.json next to the
  # artifacts in system.build.ghafFlashImages. Lets external CI / hw-test
  # automation discover, per-target:
  #   - which files this output contains and what role each plays
  #   - which flasher entrypoint to run against them
  #   - what signing applies (so the consumer does not need to re-sign)
  #
  # The flasher itself is a separate flake package; per ghaf convention the
  # consumer builds .#packages.x86_64-linux.<target>-flash-script (or
  # -flash-qspi) using the same <target> attribute it used to build these
  # images. The manifest therefore does not embed a flake attribute name —
  # the consumer already knows it.
  #
  # Schema (schema_version=1):
  #   host_name           : NixOS hostName of the target configuration.
  #   transport           : "initrd-mass-storage" | "qspi-only".
  #                         initrd-mass-storage: full 2-stage flash; artifacts
  #                         here are written to eMMC after firmware over USB.
  #                         qspi-only: artifacts list is empty; the flasher
  #                         only writes platform firmware to QSPI.
  #   flasher.entrypoint  : Path inside the <target>-flash-script package to
  #                         the executable.
  #   flasher.system      : Nix system the flasher binary is built for.
  #   flasher.target_drives : Drives the flasher can write the rootfs to,
  #                         selected via its `--target=<name>` CLI flag.
  #                         Empty for qspi-only (no rootfs written).
  #   artifacts[].name    : Filename inside this output directory.
  #   artifacts[].role    : "esp" | "root".
  #   artifacts[].compression : "zstd".
  #   artifacts[].partition.gpt_type : sgdisk type code (EF00, 8300, ...).
  #   artifacts[].partition.label    : GPT partition name expected on device.
  #   artifacts[].partition.size_mib : MiB for fixed-size partitions, "auto"
  #                                    for the trailing fill-to-end one.
  #   signing.firmware_pkc_signed : true iff jetpack PKC signing is enabled.
  #   signing.esp_secureboot      : reserved; currently always false.
  #   signing.root_dmverity       : reserved; currently always false.
  #
  # Bump schema_version on any breaking change so consumers can fail loudly.
  flashManifest = pkgs.writeText "flash-manifest.json" (
    builtins.toJSON {
      schema_version = 1;
      host_name = config.networking.hostName;
      transport = if cfg.flashScriptOverrides.onlyQSPI then "qspi-only" else "initrd-mass-storage";
      flasher = {
        entrypoint = "bin/initrd-flash-${config.networking.hostName}";
        system = "x86_64-linux";
        target_drives =
          if cfg.flashScriptOverrides.onlyQSPI then
            [ ]
          else
            [
              "emmc"
              "nvme"
              "usb"
            ];
      };
      artifacts =
        if cfg.flashScriptOverrides.onlyQSPI then
          [ ]
        else
          [
            {
              name = "esp.img.zst";
              role = "esp";
              compression = "zstd";
              partition = {
                gpt_type = "EF00";
                label = "FIRMWARE";
                size_mib = espSizeMiB;
              };
            }
            {
              name = "root.img.zst";
              role = "root";
              compression = "zstd";
              partition = {
                gpt_type = "8300";
                label = "NIXOS_ROOT";
                size_mib = "auto";
              };
            }
          ];
      signing = {
        # jetpack-nixos signs the platform-firmware blob (boot.img + bootloader
        # variants) with the upstream PKC when pkcFile is set. The flasher
        # consumes the signed blob; consumers do not need to re-sign.
        firmware_pkc_signed = jetpackCfg.firmware.secureBoot.pkcFile != null;
        # ESP and root images are produced unsigned. UEFI Secure Boot for the
        # ESP and dm-verity for root are out of scope for the current flow.
        esp_secureboot = false;
        root_dmverity = false;
      };
    }
  );

  # First-boot service: load Nix store registration and create system profile.
  # make-ext4-fs.nix ships raw store paths + /nix-path-registration but does not
  # populate the Nix DB or set up /nix/var/nix/profiles/system.
  ensureSystemProfile = pkgs.writeShellApplication {
    name = "ghaf-ensure-system-profile";
    runtimeInputs = with pkgs; [
      coreutils
      nix
    ];
    text = ''
      set -euo pipefail

      profile=/nix/var/nix/profiles/system
      registration=/nix-path-registration
      current_system=$(readlink -f /run/current-system)
      generation_link=/nix/var/nix/profiles/system-1-link

      if [ -z "$current_system" ] || [ ! -e "$current_system" ]; then
        echo "Current system closure is unavailable" >&2
        exit 1
      fi

      if [ ! -f "$registration" ] && [ -L "$profile" ] && [ "$(readlink -f "$profile")" = "$current_system" ]; then
        exit 0
      fi

      if [ -f "$registration" ]; then
        nix-store --load-db < "$registration"
        rm -f "$registration"
        touch /etc/NIXOS
      fi

      mkdir -p /nix/var/nix/profiles
      ln -sfn "$current_system" "$generation_link"
      ln -sfn system-1-link "$profile"
    '';
  };

  mkESPContentSource = pkgs.replaceVars ./mk-esp-contents.py {
    inherit (pkgs.buildPackages) python3;
  };
  mkESPContent =
    pkgs.runCommand "mk-esp-contents"
      {
        nativeBuildInputs = with pkgs; [
          mypy
          python3
        ];
      }
      ''
        install -m755 ${mkESPContentSource} $out
        mypy \
          --no-implicit-optional \
          --disallow-untyped-calls \
          --disallow-untyped-defs \
          $out
      '';

  fdtPath = "${config.hardware.deviceTree.package}/${config.hardware.deviceTree.name}";

  # ESP image: FAT32 with systemd-boot, kernel, initrd, device tree
  espSizeMiB = 256;
  espSizeBytes = espSizeMiB * 1024 * 1024;

  espImage =
    pkgs.runCommand "esp.img"
      {
        nativeBuildInputs = with pkgs; [
          dosfstools
          mtools
        ];
      }
      ''
        espDir=$(mktemp -d)
        ${mkESPContent} \
          --toplevel ${config.system.build.toplevel} \
          --output "$espDir" \
          --device-tree ${fdtPath}

        truncate -s ${toString espSizeBytes} $out
        mkfs.vfat -F 32 -n FIRMWARE $out
        cd "$espDir"
        for d in $(find . -type d | sort); do
          mmd -i $out "::$d" 2>/dev/null || true
        done
        for f in $(find . -type f); do
          mcopy -i $out "$f" "::$f"
        done
      '';

  # Root image: ext4 containing the NixOS closure, auto-sized to contents
  rootImage = pkgs.callPackage (modulesPath + "/../lib/make-ext4-fs.nix") {
    storePaths = [ config.system.build.toplevel ];
    volumeLabel = "NIXOS_ROOT";
    populateImageCommands = ''
      mkdir -p ./files/etc
      touch ./files/etc/NIXOS
      echo "${config.system.build.toplevel}" > ./files/etc/.nixos-toplevel
      cp ${config.system.build.toplevel}/etc/os-release ./files/etc/os-release
    '';
  };
in
{
  config =
    lib.mkIf
      (
        cfg.enable
        && cfg.flashScriptOverrides.method == "initrd"
        && !(options ? ghaf.partitioning.verity.enable && config.ghaf.partitioning.verity.enable)
      )
      {
        boot.loader.grub.enable = false;

        fileSystems."/" = {
          device = "/dev/disk/by-label/NIXOS_ROOT";
          fsType = "ext4";
          autoResize = true;
        };

        fileSystems."/boot" = {
          device = "/dev/disk/by-label/FIRMWARE";
          fsType = "vfat";
        };

        systemd.services.ghaf-ensure-system-profile = {
          description = "Ensure persistent NixOS system profile exists";
          wantedBy = [ "multi-user.target" ];
          before = [ "nix-gc.service" ];
          after = [ "local-fs.target" ];
          serviceConfig = {
            Type = "oneshot";
            ExecStart = "${ensureSystemProfile}/bin/ghaf-ensure-system-profile";
          };
        };

        system.build.ghafFlashImages =
          pkgs.runCommand "ghaf-flash-images"
            {
              nativeBuildInputs = [ pkgs.zstd ];
            }
            ''
              mkdir -p $out
              ${lib.optionalString (!cfg.flashScriptOverrides.onlyQSPI) ''
                zstd -19 -T$NIX_BUILD_CORES ${espImage} -o $out/esp.img.zst
                zstd -19 -T$NIX_BUILD_CORES ${rootImage} -o $out/root.img.zst
              ''}
              cp ${flashManifest} $out/flash-manifest.json
            '';
      };
}
