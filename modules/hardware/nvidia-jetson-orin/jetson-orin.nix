# Copyright 2022-2023 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# Configuration for NVIDIA Jetson Orin AGX/NX reference boards
{
  lib,
  pkgs,
  config,
  nixpkgs,
  ...
}: let
  cfg = config.ghaf.hardware.nvidia.orin;
  somDefinition = {
    "agx" = {
      flashArgs = ["-r" config.hardware.nvidia-jetpack.flashScriptOverrides.targetBoard "mmcblk0p1"];
      passthrough-patch = ./pci-passthrough-agx-test.patch;
      vfio-pci = "vfio-pci.ids=10ec:c82f";
      deviceTree = "tegra234-p3701-host-passthrough.dtb";
      buspath = [
        {
          bus = "pci";
          path = "0001:01:00.0";
        }
      ];
      kernelParams = [];
    };
    "nx" = {
      flashArgs = ["-r" config.hardware.nvidia-jetpack.flashScriptOverrides.targetBoard "nvme0n1p1"];
      # This patch uses Alex Williamson's patch for enabling overrides for missing ACS capabilities on pci
      # bus which could be accessed from following link: https://lkml.org/lkml/2013/5/30/513
      passthrough-patch = ./pci-passthrough-nx-test.patch;
      # Multiple device passing option
      #      vfio-pci = "vfio-pci.ids=10de:229c,10ec:8168";
      vfio-pci = "vfio-pci.ids=10ec:8168";
      deviceTree = "tegra234-p3767-host-passthrough.dtb";
      buspath = [
        # Multiple devices and path could be passed through this option
        #        {
        #          bus = "pci";
        #          path = "0008:00:00.0";
        #        }
        {
          bus = "pci";
          path = "0008:01:00.0";
        }
      ];
      kernelParams = [
        "pci=nomsi"
        "pcie_acs_override=downstream,multifunction"
      ];
    };
  };
  netvmExtraModules = [
    {
      # This is the device dependent part of netvm configuration.
      # This part should be conditional for AGX 01:01 for NX 08:01
      microvm.devices = somDefinition."${cfg.somType}".buspath;
      microvm.kernelParams = somDefinition."${cfg.somType}".kernelParams;
    }
  ];
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
          flashArgs = lib.mkForce somDefinition."${cfg.somType}".flashArgs;
        };

        firmware.uefi.logo = ../../../docs/src/img/1600px-Ghaf_logo.svg;
      };

      nixpkgs.hostPlatform.system = "aarch64-linux";

      ghaf.boot.loader.systemd-boot-dtb.enable = true;

      ghaf.virtualization.microvm.netvm = {
        enable = true;
        extraModules = netvmExtraModules;
      };

      boot.loader = {
        efi.canTouchEfiVariables = true;
        systemd-boot.enable = true;
      };
      boot.modprobeConfig.enable = true;
      boot.kernelPatches = [
        {
          name = "passthrough-patch";
          patch = somDefinition."${cfg.somType}".passthrough-patch;
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
        name = somDefinition."${cfg.somType}".deviceTree;
      };

      # Passthrough Jetson Orin Network cards
      boot.kernelModules = ["vfio_pci" "vfio_iommu_type1" "vfio"];

      boot.kernelParams = [
        somDefinition."${cfg.somType}".vfio-pci
        "vfio_iommu_type1.allow_unsafe_interrupts=1"
      ];
    };
  }
