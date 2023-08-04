# Copyright 2022-2023 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# Module which configures sd-image to generate images to be used with NVIDIA
# Jetson Orin AGX/NX devices. Supposed to be imported from format-module.nix.
#
# Generates ESP partition contents mimicking systemd-boot installation. Can be
# used to generate both images to be used in flashing script, and image to be
# flashed to external disk. NVIDIA's edk2 does not seem to care to much about
# the partition types, as long as there is a FAT partition, which contains
# EFI-directory and proper kind of structure, it finds the EFI-applications and
# boots them successfully.
#
{
  config,
  pkgs,
  modulesPath,
  lib,
  ...
}: {
  imports = [
    (modulesPath + "/installer/sd-card/sd-image.nix")
  ];

  boot.loader.grub.enable = false;
  disabledModules = [(modulesPath + "/profiles/all-hardware.nix")];

  sdImage = let
    mkESPContent = pkgs.substituteAll {
      src = ./mk-esp-contents.py;
      isExecutable = true;
      inherit (pkgs.buildPackages) python3;
    };
    fdtPath = "${config.hardware.deviceTree.package}/${config.hardware.deviceTree.name}";
  in {
    firmwareSize = 256;
    populateFirmwareCommands = ''
      mkdir -pv firmware
      ${mkESPContent} --toplevel ${config.system.build.toplevel} --output firmware/ --device-tree ${fdtPath}
    '';
    populateRootCommands = ''
    '';
    postBuildCommands = ''
      wc -c firmware_part.img > $out/esp.size
      wc -c root-fs.img > $out/root.size

      ${pkgs.pkgsBuildHost.zstd}/bin/zstd firmware_part.img -o $out/esp.img.zst
      ${pkgs.pkgsBuildHost.zstd}/bin/zstd root-fs.img -o $out/root.img.zst
    '';
  };

  fileSystems."/boot" = {
    device = "/dev/disk/by-label/${config.sdImage.firmwarePartitionName}";
    fsType = "vfat";
  };
}
