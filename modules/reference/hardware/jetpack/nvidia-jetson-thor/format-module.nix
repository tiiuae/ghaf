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
  mkESPContentSource = pkgs.replaceVars ../nvidia-jetson-orin/mk-esp-contents.py {
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

  firmwareSize = 256; # MB
  firmwareLabel = "FIRMWARE";
  rootLabel = "NIXOS_SD";

  rootfsImage = pkgs.callPackage (modulesPath + "/../lib/make-ext4-fs.nix") {
    storePaths = config.system.build.toplevel;
    volumeLabel = rootLabel;
    uuid = "44444444-4444-4444-8888-888888888888";
    populateImageCommands = "";
  };

  imageName = "thor-${config.system.nixos.label}-${pkgs.stdenv.hostPlatform.system}.img";

  ghafImage = pkgs.callPackage (
    {
      stdenv,
      dosfstools,
      gptfdisk,
      mtools,
      util-linux,
      zstd,
    }:
    stdenv.mkDerivation {
      name = "thor-sd-image";

      nativeBuildInputs = [
        dosfstools
        gptfdisk
        mtools
        util-linux
        zstd
      ];

      buildCommand = ''
        mkdir -p $out/sd-image

        firmwareSizeSectors=$((${toString firmwareSize} * 1024 * 1024 / 512))
        rootfsSizeBytes=$(stat -c %s ${rootfsImage})
        rootfsSizeSectors=$(( (rootfsSizeBytes + 511) / 512 ))

        espStart=2048
        espEnd=$((espStart + firmwareSizeSectors - 1))
        rootStart=$((espEnd + 1))
        rootEnd=$((rootStart + rootfsSizeSectors - 1))
        totalSectors=$((rootEnd + 1 + 33))

        echo "Creating GPT image..."
        echo "  ESP: sectors $espStart - $espEnd (${toString firmwareSize} MB)"
        echo "  Root: sectors $rootStart - $rootEnd ($((rootfsSizeSectors / 2048)) MB)"
        echo "  Total: $totalSectors sectors ($((totalSectors / 2048)) MB)"

        truncate -s $((totalSectors * 512)) $out/sd-image/${imageName}
        img=$out/sd-image/${imageName}

        sgdisk --clear \
          --new=1:$espStart:$espEnd --typecode=1:EF00 --change-name=1:${firmwareLabel} \
          --new=2:$rootStart:$rootEnd --typecode=2:8300 --change-name=2:${rootLabel} \
          $img

        truncate -s $((firmwareSizeSectors * 512)) esp.img
        mkfs.vfat -n ${firmwareLabel} esp.img

        mkdir -p firmware
        ${mkESPContent} \
          --toplevel ${config.system.build.toplevel} \
          --output firmware/

        for item in firmware/*; do
          mcopy -i esp.img -s "$item" ::
        done

        dd if=esp.img of=$img bs=512 seek=$espStart conv=notrunc
        dd if=${rootfsImage} of=$img bs=512 seek=$rootStart conv=notrunc

        zstd -T0 --rm $img
      '';
    }
  ) { };
in
{
  options.image.fileName = lib.mkOption {
    type = lib.types.str;
    default = "${imageName}.zst";
    description = "Name of the generated image file";
  };

  config = {
    boot.loader.grub.enable = false;
    hardware.enableAllHardware = lib.mkForce false;

    system.build.ghafImage = ghafImage;

    fileSystems."/boot" = {
      device = "/dev/disk/by-label/${firmwareLabel}";
      fsType = "vfat";
    };

    fileSystems."/" = {
      device = "/dev/disk/by-label/${rootLabel}";
      fsType = "ext4";
    };
  };
}
