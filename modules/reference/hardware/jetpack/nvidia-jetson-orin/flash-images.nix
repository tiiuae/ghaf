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
  lib,
  ...
}:
let
  cfg = config.ghaf.hardware.nvidia.orin;

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
  config = lib.mkIf cfg.enable {
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
          zstd -19 -T$NIX_BUILD_CORES ${espImage} -o $out/esp.img.zst
          zstd -19 -T$NIX_BUILD_CORES ${rootImage} -o $out/root.img.zst
        '';
  };
}
