# Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# Module for Hardware Definitions
#
# The point of this module is to only store information about the hardware
# configuration, and the logic that uses this information should be elsewhere.
{lib, ...}: let
  inherit (lib) mkOption types literalExpression;
in {
  options.ghaf.hardware.definition = let
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
        name = mkOption {
          type = types.nullOr types.str;
          default = null;
          description = ''
            PCI device name (optional)
          '';
        };
      };
    };

    # USB device submodule, defined either by product ID and vendor ID, or by bus and port number
    usbDevSubmodule = types.submodule {
      options = {
        name = mkOption {
          type = types.nullOr types.str;
          default = null;
          description = ''
            USB device name. NOT optional for external devices, in which case it must not contain spaces
            or extravagant characters.
          '';
        };
        vendorId = mkOption {
          type = types.nullOr types.str;
          default = null;
          description = ''
            USB Vendor ID (optional). If this is set, the productId must also be set.
          '';
        };
        productId = mkOption {
          type = types.nullOr types.str;
          default = null;
          description = ''
            USB Product ID (optional). If this is set, the vendorId must also be set.
          '';
        };
        hostbus = mkOption {
          type = types.nullOr types.str;
          default = null;
          description = ''
            USB device bus number (optional). If this is set, the hostport must also be set.
          '';
        };
        hostport = mkOption {
          type = types.nullOr types.str;
          default = null;
          description = ''
            USB device device number (optional). If this is set, the hostbus must also be set.
          '';
        };
      };
    };

    # Input devices submodule
    inputDevSubmodule = types.submodule {
      options = {
        name = mkOption {
          type = types.listOf types.str;
          default = [];
          description = ''

          '';
        };
        evdev = mkOption {
          type = types.listOf types.str;
          default = [];
          description = ''

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

    input = {
      keyboard = mkOption {
        description = "Name of the keyboard device(s)";
        type = inputDevSubmodule;
        default = {};
      };

      mouse = mkOption {
        description = "Name of the mouse device(s)";
        type = inputDevSubmodule;
        default = {};
      };

      touchpad = mkOption {
        description = "Name of the touchpad device(s)";
        type = inputDevSubmodule;
        default = {};
      };

      misc = mkOption {
        description = "Name of the misc device(s)";
        type = inputDevSubmodule;
        default = {};
      };
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

    disks = mkOption {
      description = "Disks to format and mount";
      type = types.attrsOf (types.submodule {
        options.device = mkOption {
          type = types.str;
          description = ''
            Path to the disk
          '';
        };
      });
      default = {};
      example = literalExpression ''
        {
          disk1.device = "/dev/nvme0n1";
        }
      '';
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

    udevRules = mkOption {
      description = ''
        Definition of required udev rules.
      '';
      type = types.str;
      default = "";
      example = literalExpression ''
        # Laptop keyboard
        SUBSYSTEM=="input",ATTRS{name}=="AT Translated Set 2 keyboard",GROUP="kvm"
      '';
    };

    audio = {
      # With the current implementation, the whole PCI IOMMU group 14:
      #   00:1f.x in the example from Lenovo X1 Carbon
      #   must be defined for passthrough to AudioVM
      pciDevices = mkOption {
        description = "PCI Devices to passthrough to AudioVM";
        type = types.listOf pciDevSubmodule;
        default = [];
        example = literalExpression ''
          [
            {
              path = "0000:00:1f.0";
              vendorId = "8086";
              productId = "519d";
            }
            {
              path = "0000:00:1f.3";
              vendorId = "8086";
              productId = "51ca";
            }
            {
              path = "0000:00:1f.4";
              vendorId = "8086";
              productId = "51a3";
            }
            {
              path = "0000:00:1f.5";
              vendorId = "8086";
              productId = "51a4";
            }
          ]
        '';
      };
      kernelParams = mkOption {
        description = "Hardware specific kernel parameters for audio devices";
        type = types.listOf types.str;
        default = [];
        example = literalExpression ''
          [
            "snd_intel_dspcfg.dsp_driver=3"
            "snd_sof_intel_hda_common.dmic_num=4"
          ]
        '';
      };
    };

    usb = {
      internal = mkOption {
        description = ''
          Internal USB device(s) to passthrough.

          Each device definition requires a name, and either vendorId and productId, or hostbus and hostport.
          The latter is useful for addressing devices that may have different vendor and product IDs in the
          same hardware generation.

          Note that internal devices must follow the naming convention to be correctly identified
          and subsequently used. Current special names are:
            - 'webcam' for the internal webcam device
            - 'fprint-reader' for the internal fingerprint reader device
        '';
        type = types.listOf usbDevSubmodule;
        default = [];
        example = literalExpression ''
          [
            {
              name = "webcam";
              vendorId = "0123";
              productId = "0123";
            }
            {
              name = "fprint-reader";
              hostbus = "3";
              hostport = "3";
            }
          ]
        '';
      };
      external = mkOption {
        description = "External USB device(s) to passthrough. Requires name, vendorId, and productId.";
        type = types.listOf usbDevSubmodule;
        default = [];
        example = literalExpression ''
          [
            {
              name = "external-device-1";
              vendorId = "0123";
              productId = "0123";
            }
            {
              name = "external-device-2";
              vendorId = "0123";
              productId = "0123";
            }
          ]
        '';
      };
    };
  };
}
