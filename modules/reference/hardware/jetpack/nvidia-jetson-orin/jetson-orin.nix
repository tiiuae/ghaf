# Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# Configuration for NVIDIA Jetson Orin AGX/NX reference boards
{
  pkgs,
  lib,
  config,
  ...
}:
let
  cfg = config.ghaf.hardware.nvidia.orin;
  inherit (lib)
    mkEnableOption
    mkOption
    mkIf
    types
    ;
in
{
  options.ghaf.hardware.nvidia.orin = {
    # Enable the Orin boards
    enable = mkEnableOption "Orin hardware";

    flashScriptOverrides.onlyQSPI = mkEnableOption "to only flash QSPI partitions, i.e. disable flashing of boot and root partitions to eMMC";

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
        flashArgs = lib.mkForce [
          "-r"
          config.hardware.nvidia-jetpack.flashScriptOverrides.targetBoard
          "mmcblk0p1"
        ];
      };

      firmware.uefi = {
        logo = ../../../../../docs/src/img/1600px-Ghaf_logo.svg;
        edk2NvidiaPatches = [
          # This effectively disables EFI FB Simple Framebuffer, which does
          # not work properly but causes kernel panic during the boot if the
          # HDMI cable is connected during boot time.
          #
          # The patch reverts back to old behavior, which is to always reset
          # the display when exiting UEFI, instead of doing handoff, when
          # means not to reset anything.
          # ./edk2-nvidia-always-reset-display.patch
        ];
      };
    };

    nixpkgs.hostPlatform.system = "aarch64-linux";

    ghaf.boot.loader.systemd-boot-dtb.enable = true;

    boot = {
      loader = {
        efi.canTouchEfiVariables = true;
        systemd-boot.enable = true;
      };

      modprobeConfig.enable = true;

      kernelPatches = [
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
    };

    services.nvpmodel = {
      enable = lib.mkDefault true;
      # Enable all CPU cores, full power consumption (50W on AGX, 25W on NX)
      profileNumber = lib.mkDefault 3;
    };
    hardware.deviceTree =
      {
        enable = lib.mkDefault true;
        dtbSource = "${pkgs.nvidia-jetpack.bspSrc}/kernel/dtb/";
        # Add the include paths to build the dtb overlays
        dtboBuildExtraIncludePaths = [
          "${lib.getDev config.hardware.deviceTree.kernelPackage}/lib/modules/${config.hardware.deviceTree.kernelPackage.modDirVersion}/source/nvidia/soc/t23x/kernel-include"
        ];
      }

      # NOTE: "-nv.dtb" files are from NVIDIA's BSP
      # Versions of the device tree without PCI passthrough related
      # modifications.
      // lib.optionalAttrs (cfg.somType == "agx") {
        name = lib.mkDefault "tegra234-p3737-0000+p3701-0000-nv.dtb";
      }
      // lib.optionalAttrs (cfg.somType == "nx") {
        # Sake of clarity: Jetson 35.4 and IO BASE B carrier board
        # uses "tegra234-p3767-0000-p3509-a02.dtb"-device tree.
        # p3509-a02 == IO BASE B carrier board
        # p3767-0000 == Orin NX SOM
        # p3768-0000 == Official NVIDIA's carrier board
        # Upstream kernel has only official carrier board device tree,
        # but it works with IO BASE B carrier board with minor
        # modifications.
        name = lib.mkDefault "tegra234-p3768-0000+p3767-0000-nv.dtb";
      };
  };
}
