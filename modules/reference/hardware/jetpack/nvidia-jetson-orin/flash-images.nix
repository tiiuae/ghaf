# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  config,
  pkgs,
  modulesPath,
  lib,
  ...
}:
let
  cfg = config.ghaf.hardware.nvidia.orin;

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

  # ESP image
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

  # For symlinks into /nix/store
  inherit (config.system.build) toplevel;
  systemBaseName = baseNameOf toplevel;

  # Root image: ext4 containing the full NixOS closure (incl. boot)
  rootImage = pkgs.callPackage (modulesPath + "/../lib/make-ext4-fs.nix") {
    storePaths = [
      config.system.build.toplevel
      config.boot.kernelPackages.kernel
      config.system.build.initialRamdisk
      config.system.build.bootStage2
    ];

    volumeLabel = "NIXOS_ROOT";

    # NOTE: Correct parameter name is populateImageCommands
    # make-ext4-fs.nix will itself add /nix-path-registration to rootImage.
    populateImageCommands = ''
      mkdir -p ./files
      mkdir -p ./files/etc
      mkdir -p ./files/run
      mkdir -p ./files/nix/var/nix/profiles
      mkdir -p ./files/nix/var/nix/gcroots/profiles

      # Mark as NixOS and pin the toplevel path for traceability
      echo -n > ./files/etc/NIXOS
      echo "${toplevel}" > ./files/etc/.nixos-toplevel
      cp ${toplevel}/etc/os-release ./files/etc/os-release

      # GC roots that protect the system even before profile is set
      ln -sfn /nix/store/${systemBaseName} ./files/nix/var/nix/gcroots/profiles/system
      ln -sfn /nix/store/${systemBaseName} ./files/run/current-system
      ln -sfn /nix/store/${systemBaseName} ./files/run/booted-system

      # Let systemd generate a machine-id
      : > ./files/etc/machine-id
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

    # >>> First-boot finalization (mirrors sd-image.nix) <<<
    # Loads /nix-path-registration written by make-ext4-fs.nix and
    # sets the "system" profile so GC roots are persistent thereafter.
    boot.postBootCommands = ''
      set -eu
      reg="/nix-path-registration"
      if [ -f "$reg" ]; then
        ${config.nix.package.out}/bin/nix-store --load-db < "$reg"
        touch /etc/NIXOS
        ${config.nix.package.out}/bin/nix-env -p /nix/var/nix/profiles/system --set /run/current-system
        rm -f "$reg"
      fi
    '';

    system.build.ghafFlashImages =
      pkgs.runCommand "ghaf-flash-images" { nativeBuildInputs = [ pkgs.zstd ]; }
        ''
          mkdir -p $out
          zstd -19 -T$NIX_BUILD_CORES ${espImage} -o $out/esp.img.zst
          zstd -19 -T$NIX_BUILD_CORES ${rootImage} -o $out/root.img.zst
        '';
  };
}
