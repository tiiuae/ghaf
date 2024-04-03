# Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# Configuration for NVIDIA Jetson Orin AGX/NX reference boards
{
  lib,
  config,
  ...
}: let
  cfg = config.ghaf.hardware.nvidia.orin;
in
  with lib; {
    options.ghaf.hardware.nvidia.orin = {
      # Enable the Orin boards
      enable = mkEnableOption "Orin hardware";

      flashScriptOverrides.onlyQSPI =
        mkEnableOption
        "to only flash QSPI partitions, i.e. disable flashing of boot and root partitions to eMMC";

      flashScriptOverrides.preFlashCommands = mkOption {
        description = "Commands to run before the actual flashing";
        type = types.str;
        default = "";
      };

      somType = mkOption {
        description = "SoM config Type (NX|AGX|Nano)";
        type = types.str;
        default = "agx";
      };

      carrierBoard = mkOption {
        description = "Board Type";
        type = types.str;
        default = "devkit";
      };
    };

    config = mkIf cfg.enable {
      hardware.nvidia-jetpack = {
        enable = true;
        som = "orin-${cfg.somType}";
        carrierBoard = "${cfg.carrierBoard}";
        modesetting.enable = true;

        flashScriptOverrides = lib.optionalAttrs (cfg.somType == "agx") {
          flashArgs = lib.mkForce ["-r" config.hardware.nvidia-jetpack.flashScriptOverrides.targetBoard "mmcblk0p1"];
        };

        firmware.uefi = {
          logo = ../../../docs/src/img/1600px-Ghaf_logo.svg;
          edk2NvidiaPatches = [
            # This effectively disables EFI FB Simple Framebuffer, which does
            # not work properly but causes kernel panic during the boot if the
            # HDMI cable is connected during boot time.
            #
            # The patch reverts back to old behavior, which is to always reset
            # the display when exiting UEFI, instead of doing handoff, when
            # means not to reset anything.
            ./edk2-nvidia-always-reset-display.patch
          ];
        };
      };

      nixpkgs.hostPlatform.system = "aarch64-linux";

      ghaf.boot.loader.systemd-boot-dtb.enable = true;

      boot.loader = {
        efi.canTouchEfiVariables = true;
        systemd-boot.enable = true;
      };
      boot.modprobeConfig.enable = true;
      boot.kernelPatches = [
        {
          name = "vsock-config";
          patch = null;
          extraStructuredConfig = with lib.kernel; {
            VHOST = yes;
            VHOST_MENU = yes;
            VHOST_IOTLB = yes;
            VHOST_VSOCK = yes;
            VSOCKETS = yes;
            VSOCKETS_DIAG = yes;
            VSOCKETS_LOOPBACK = yes;
            VIRTIO_VSOCKETS_COMMON = yes;
          };
        }
      ];

      services.nvpmodel = {
        enable = lib.mkDefault true;
        # Enable all CPU cores, full power consumption (50W on AGX, 25W on NX)
        profileNumber = lib.mkDefault 3;
      };
      hardware.deviceTree =
        {
          enable = lib.mkDefault true;
        }
        # Versions of the device tree without PCI passthrough related
        # modifications.
        // lib.optionalAttrs (cfg.somType == "agx") {
          name = lib.mkDefault "tegra234-p3701-0000-p3737-0000.dtb";
        }
        // lib.optionalAttrs (cfg.somType == "nx") {
          name = lib.mkDefault "tegra234-p3767-0000-p3509-a02.dtb";
        };
    };
  }
