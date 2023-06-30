# Copyright 2022-2023 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# Configuration for NVIDIA Jetson AGX Orin
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

        flashScriptOverrides = {
          flashArgs = lib.mkForce ["-r" config.hardware.nvidia-jetpack.flashScriptOverrides.targetBoard "mmcblk0p1"];
        };

        firmware.uefi.logo = ../../../docs/src/img/1600px-Ghaf_logo.svg;
      };

      nixpkgs.hostPlatform.system = "aarch64-linux";

      ghaf.boot.loader.systemd-boot-dtb.enable = true;

      boot.loader = {
        efi.canTouchEfiVariables = true;
        systemd-boot.enable = true;
      };

      boot.kernelPatches = [
        {
          name = "passthrough-patch";
          patch = ./pci-passthrough-test.patch;
        }
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

      hardware.deviceTree = {
        enable = true;
        name = "tegra234-p3701-host-passthrough.dtb";
      };

      # Passthrough Jetson Orin WiFi card
      boot.kernelParams = [
        "vfio-pci.ids=10ec:c82f"
        "vfio_iommu_type1.allow_unsafe_interrupts=1"
      ];
    };
  }
