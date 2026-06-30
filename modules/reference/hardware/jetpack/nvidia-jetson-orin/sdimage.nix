# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
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
# When ghaf.image.sdcard.uki.enable is set, the ESP is populated with a Unified
# Kernel Image (Type #2 BLS entry) instead of the traditional Type #1 entry
# produced by mk-esp-contents.py. The UKI bundles kernel, initrd, cmdline, DTB,
# and os-release into a single PE/COFF binary discovered automatically by
# systemd-boot from EFI/Linux/.
#
{
  config,
  pkgs,
  modulesPath,
  lib,
  ...
}:
let
  cfg = config.ghaf.image.sdcard;
  inherit (pkgs.stdenv.hostPlatform) efiArch;
  fdtPath = "${config.hardware.deviceTree.package}/${config.hardware.deviceTree.name}";
in
{
  imports = [ (modulesPath + "/installer/sd-card/sd-image.nix") ];

  options.ghaf.image.sdcard.uki = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Populate the SD image ESP with a Unified Kernel Image (Type #2 BLS
        entry) instead of the traditional Type #1 entries from
        mk-esp-contents.py.

        The UKI bundles kernel, initrd, cmdline, DTB, and os-release into a
        single PE/COFF binary that systemd-boot discovers automatically from
        EFI/Linux/.

        Note: Enabling this produces an image without bootloader-level
        generation rollback. A single UKI is placed in the ESP.
      '';
    };

    dtbPadding = lib.mkOption {
      type = lib.types.int;
      default = 65536;
      description = ''
        Extra padding bytes added to the device tree blob.
        systemd-stub needs room in the FDT for runtime modifications
        (e.g. adding /chosen properties). Increase if firmware rejects
        the DTB with "Invalid header detected on UEFI supplied FDT".
      '';
    };
  };

  config = {
    boot.loader.grub.enable = false;
    hardware.enableAllHardware = lib.mkForce false;

    # Jetson-specific UKI build configuration
    boot.uki.settings = lib.mkIf cfg.uki.enable (
      let
        # When packed in a UKI, the dtb needs some padding to avoid error:
        # "Invalid header detected on UEFI supplied FDT"
        # The default value of 64K for dtbPadding should be more than enough.
        paddedDtb =
          pkgs.runCommand "padded-dtb"
            {
              nativeBuildInputs = [ pkgs.dtc ];
            }
            ''
              mkdir -p $out
              dtc -I dtb -O dtb -p ${toString cfg.uki.dtbPadding} ${fdtPath} -o $out/padded.dtb
            '';
      in
      {
        UKI = {
          DeviceTree = "${paddedDtb}/padded.dtb";
        };
      }
    );

    sdImage =
      let
        # Type #1 BLS entry (uses mk-esp-contents.py)
        # TODO do we really need replaceVars just to set the python string in the
        # shbang?
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
      in
      {
        firmwareSize = if cfg.uki.enable then 512 else 256;

        populateFirmwareCommands =
          if cfg.uki.enable then
            ''
              mkdir -pv firmware/EFI/BOOT
              mkdir -pv firmware/EFI/Linux
              mkdir -pv firmware/loader

              # Install systemd-boot as the UEFI bootloader
              cp -v ${pkgs.systemd}/lib/systemd/boot/efi/systemd-boot${efiArch}.efi \
                    firmware/EFI/BOOT/BOOT${lib.toUpper efiArch}.EFI

              # Install the UKI (Type #2 entry). systemd-boot discovers it
              # automatically from EFI/Linux/
              cp -v ${config.system.build.uki}/${config.system.boot.loader.ukiFile} \
                    firmware/EFI/Linux/${config.system.boot.loader.ukiFile}

              # Minimal loader configuration
              cat > firmware/loader/loader.conf << EOF
              timeout 0
              editor no
              console-mode keep
              EOF
            ''
          else
            ''
              mkdir -pv firmware
              ${mkESPContent} \
                --toplevel ${config.system.build.toplevel} \
                --output firmware/ \
                --device-tree ${fdtPath}
            '';

        populateRootCommands = "";

        postBuildCommands = ''
          fdisk_output=$(fdisk -l "$img")

          # Offsets and sizes are in 512 byte sectors
          blocksize=512

          # ESP partition offset and sector count
          part_esp=$(echo -n "$fdisk_output" | tail -n 2 | head -n 1 | tr -s ' ')
          part_esp_begin=$(echo -n "$part_esp" | cut -d ' ' -f2)
          part_esp_count=$(echo -n "$part_esp" | cut -d ' ' -f4)

          # root-partition offset and sector count
          part_root=$(echo -n "$fdisk_output" | tail -n 1 | head -n 1 | tr -s ' ')
          part_root_begin=$(echo -n "$part_root" | cut -d ' ' -f3)
          part_root_count=$(echo -n "$part_root" | cut -d ' ' -f4)

          echo -n $part_esp_begin > $out/esp.offset
          echo -n $part_esp_count > $out/esp.size
          echo -n $part_root_begin > $out/root.offset
          echo -n $part_root_count > $out/root.size
        '';
      };

    #TODO: should we use the default
    #https://github.com/NixOS/nixpkgs/blob/master/nixos/modules/installer/sd-card/sd-image.nix#L177
    fileSystems."/boot" = {
      device = "/dev/disk/by-label/${config.sdImage.firmwarePartitionName}";
      fsType = "vfat";
    };
  };
}
