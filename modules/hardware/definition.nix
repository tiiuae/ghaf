# Copyright 2022-2023 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# Module for Hardware Definitions
#
# The point of this module is to only store information about the hardware
# configuration, and the logic that uses this information should be elsewhere.
{lib, ...}: {
  options.ghaf.hardware.definition = with lib; let
    pciDevSubmodule = types.submodule {
      options = {
        path = mkOption {
          type = types.str;
          description = ''
            PCI device path
          '';
        };
        vendorId = mkOption {
          type = types.nullOr types.str;
          default = null;
          description = ''
            PCI Vendor ID (optional)
          '';
        };
        productId = mkOption {
          type = types.nullOr types.str;
          default = null;
          description = ''
            PCI Product ID (optional)
          '';
        };
      };
    };
  in {
    name = mkOption {
      description = "Name of the hardware";
      type = types.str;
      default = "";
    };

    network = {
      # TODO? Should add NetVM enabler here?
      # netvm.enable = mkEnableOption = "NetVM";

      pciDevices = mkOption {
        description = "PCI Devices to passthrough to NetVM";
        type = types.listOf pciDevSubmodule;
        default = [];
        example = literalExpression ''
          [{
            path = "0000:00:14.3";
            vendorId = "8086";
            productId = "51f1";
          }]
        '';
      };
    };

    gpu = {
      # TODO? Should add GuiVM enabler here?
      # guivm.enable = mkEnableOption = "NetVM";

      pciDevices = mkOption {
        description = "PCI Devices to passthrough to GuiVM";
        type = types.listOf pciDevSubmodule;
        default = [];
        example = literalExpression ''
          [{
            path = "0000:00:02.0";
            vendorId = "8086";
            productId = "a7a1";
          }]
        '';
      };
    };

    virtioInputHostEvdevs = mkOption {
      description = ''
        List of input device files to passthrough to GuiVM using
        "-device virtio-input-host-pci,evdev=" QEMU command line argument.
      '';
      type = types.listOf types.str;
      default = [];
      example = literalExpression ''
        [
          "evdev=/dev/input/by-path/platform-i8042-serio-0-event-kbd"
          "evdev=/dev/mouse"
          "evdev=/dev/touchpad"
          "evdev=/dev/input/by-path/platform-i8042-serio-1-event-mouse"
        ]
      '';
    };
  };
}
