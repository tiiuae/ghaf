# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# Configuration for NVIDIA Jetson Thor AGX reference boards
{
  lib,
  config,
  ...
}:
let
  cfg = config.ghaf.hardware.nvidia.thor;
  inherit (lib)
    mkEnableOption
    mkOption
    mkIf
    types
    ;
in
{
  _file = ./jetson-thor.nix;

  options.ghaf.hardware.nvidia.thor = {
    enable = mkEnableOption "Jetson Thor hardware";

    somType = mkOption {
      description = "SoM config type";
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
    nixpkgs.hostPlatform.system = "aarch64-linux";

    hardware.deviceTree.enable = lib.mkDefault true;

    # Enable when adjusting the device tree
    ghaf.hardware.aarch64.systemd-boot-dtb.enable = false;

    boot = {
      loader = {
        efi.canTouchEfiVariables = true;
        systemd-boot.enable = true;
      };

      modprobeConfig.enable = true;

      # Kernel patches
      kernelPatches = [
        {
          name = "vsock-config";
          patch = null;
          structuredExtraConfig = with lib.kernel; {
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

  };
}
