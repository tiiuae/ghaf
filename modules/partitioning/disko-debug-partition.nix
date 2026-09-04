# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
#
# This partition scheme is used for development & debug systems.
#
# First two partitions are related to the boot process:
# - boot : Bootloader partition
# - ESP : (500M) Kernel and initrd
#
# The third partition is a container for LVM, optionally encrypted with LUKS.
# LVM is used to create logical volumes for root, swap and persist.
#
# When deferred encryption is enabled, the image is created WITHOUT LUKS
# encryption initially. Encryption is applied on first boot when the user
# provides credentials, converting the layout to: LUKS → LVM → LVs
{
  pkgs,
  lib,
  config,
  ...
}:
let
  cfg = config.ghaf.partitioning.disko;
  defaultPassword = pkgs.writeTextFile {
    name = "disko-default-password";
    text = "";
  };
  diskName = "disk1";
  espSizeMiB = 500;
  headroomMiB = 4 * 1024; # GPT + LVM metadata
  # One slot, not two. The B slot is cut from free space on first boot by
  # btrfs-postboot, before persist claims the rest -- it was only ever an empty
  # reservation here, contributing no data to the image but doubling both the
  # virtual size and the smallest disk we can install onto.
  volumesMiB = espSizeMiB + cfg.swapSize + cfg.persistSize + cfg.rootSize + cfg.veritySize;
in
{
  _file = ./disko-debug-partition.nix;

  options.ghaf.partitioning.disko = {
    enable = lib.mkEnableOption "the disko partitioning scheme";

    imageBuilder.compression = lib.mkOption {
      type = lib.types.enum [
        "none"
        "zstd"
      ];
      description = "Compression algorithm used for the install image";
      default = "zstd";
    };

    rootSize = lib.mkOption {
      type = lib.types.int;
      default = 50 * 1024;
      example = 200 * 1024;
      description = ''
        Size of each root logical volume in MiB, applied to both A/B slots.
        An update written to the B slot has to fit where the A slot fits, so
        the two are not configurable independently. Defaults to 50 GiB.
      '';
    };

    veritySize = lib.mkOption {
      type = lib.types.int;
      default = 1 * 1024;
      description = ''
        Size of each verity logical volume in MiB, applied to both A/B slots.
        Defaults to 1 GiB.
      '';
    };

    swapSize = lib.mkOption {
      type = lib.types.int;
      default = 12 * 1024;
      description = ''
        Size of the swap logical volume in MiB. Hibernation resumes from this
        device, so it should be at least as large as RAM. Defaults to 12 GiB.
      '';
    };

    persistSize = lib.mkOption {
      type = lib.types.int;
      default = 2 * 1024;
      description = ''
        Initial size of the persist logical volume in MiB. A floor, not an
        allocation: btrfs-postboot extends it to fill the disk on first boot.
        Defaults to 2 GiB.
      '';
    };

    imageSize = lib.mkOption {
      type = lib.types.int;
      default = volumesMiB + headroomMiB;
      description = ''
        Size of the disk image in MiB. Defaults to what the volumes above
        require plus 4 GiB for GPT and LVM metadata. The image file is sparse,
        so it occupies only the space its contents actually use.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = cfg.imageSize >= volumesMiB;
        message = "ghaf.partitioning.disko.imageSize is ${toString cfg.imageSize} MiB but the volumes need ${toString volumesMiB} MiB; the A slot, swap and persist must fit.";
      }
    ];

    ghaf.partitioning.btrfs-postboot.enable = true;

    ghaf.storage.encryption.partitionDevice =
      lib.mkDefault
        config.disko.devices.disk."${diskName}".content.partitions.luks.device;

    system.build.ghafImage = lib.mkIf (
      !config.ghaf.partitioning.verity.enable
    ) config.system.build.diskoImages;
    disko = {
      imageBuilder.extraPostVM = lib.mkIf (cfg.imageBuilder.compression == "zstd") ''
        ${lib.getExe pkgs.bmaptool} create "$out/${diskName}.raw" -o "$out/ghaf-image.bmap"
        cores="''${NIX_BUILD_CORES:-1}"
        if [ "$cores" -gt 8 ]; then
          cores=8
        fi
        ${lib.getExe pkgs.zstd} -T''${cores} -4 --long --compress "$out/${diskName}.raw" -o "$out/ghaf-image.raw.zst" --rm
      '';
      devices = {
        disk."${diskName}" = {
          type = "disk";
          imageSize = "${toString cfg.imageSize}M";
          content = {
            type = "gpt";
            partitions = {
              esp = {
                name = "ESP";
                size = "${toString espSizeMiB}M";
                type = "EF00";
                content = {
                  type = "filesystem";
                  format = "vfat";
                  mountpoint = "/boot";
                  mountOptions = [
                    "umask=0077"
                    "nofail"
                  ];
                };
                priority = 2;
              };
              luks =
                let
                  # Plain LVM content without LUKS wrapper
                  plainLvmContent = {
                    type = "lvm_pv";
                    vg = "pool";
                  };
                  # LUKS-wrapped LVM content
                  encryptedLvmContent = {
                    type = "luks";
                    name = "crypted";
                    askPassword = false;
                    initrdUnlock = false;
                    settings = {
                      keyFile = "${defaultPassword}";
                    };
                    content = plainLvmContent;
                  };
                in
                {
                  size = "100%";
                  priority = 3;
                  name = "luks";
                  content =
                    if config.ghaf.storage.encryption.enable && !config.ghaf.storage.encryption.deferred then
                      encryptedLvmContent
                    else
                      plainLvmContent;
                };
            };
          };
        };

        lvm_vg = {
          pool = {
            type = "lvm_vg";
            lvs = {
              swap = {
                size = "${toString cfg.swapSize}M";
                content = {
                  type = "swap";
                  resumeDevice = true; # resume from hibernation from this device
                  randomEncryption = !config.ghaf.storage.encryption.enable;
                };
              };

              # `_0` denote version of installed system. In terms of A/B update -- debug version always `0`
              root_0 = {
                size = "${toString cfg.rootSize}M";
                content = {
                  type = "filesystem";
                  format = "ext4";
                  mountpoint = "/";
                  mountOptions = [
                    "noatime"
                    "nodiratime"
                  ];
                };
              };

              # NOTE: placeholder for A-slot verity
              verity_0 = {
                size = "${toString cfg.veritySize}M";
              };

              persist = {
                # Extended to fill the disk by btrfs-postboot
                size = "${toString cfg.persistSize}M";
                content = {
                  type = "filesystem";
                  format = "btrfs";
                  mountpoint = "/persist";
                  mountOptions = [
                    "noatime"
                    "nodiratime"
                  ];
                };
              };
            };
          };
        };
      };
    };
  };
}
