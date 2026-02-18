# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# Module for Hardware Definitions
#
# The point of this module is to only store information about the hardware
# configuration, and the logic that uses this information should be elsewhere.
{ pkgs, lib, ... }:
let
  inherit (lib) mkOption types literalExpression;
in
{
  _file = ./definition.nix;

  options.ghaf.hardware.definition =
    let
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
          qemu.deviceExtraArgs = mkOption {
            type = types.nullOr types.str;
            default = null;
            description = ''
              Device additional arguments (optional)
            '';
          };
        };
      };

      # USB device submodule
      # Defined either by product ID and vendor ID, or by bus and port number
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
          vmUdevExtraRule = mkOption {
            type = types.nullOr types.str;
            default = null;
            description = ''
              Extra udev rule for the VM to control access of the USB device.
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
            type = types.listOf types.raw;
            default = [ ];
            description = ''
              List of input device names. Can either be a string, or a list of strings.
              The list option allows to bind several input device names to the same evdev.
              This allows to create one generic hardware definition for multiple SKUs.
            '';
          };
          evdev = mkOption {
            type = types.listOf types.str;
            default = [ ];
            description = ''
              List of event devices.
            '';
          };
        };
      };

      # Kernel configuration submodule
      kernelConfig = types.submodule {
        options = {
          stage1 = {
            kernelModules = mkOption {
              description = "Hardware specific kernel modules";
              type = types.listOf types.str;
              default = [ ];
              example = literalExpression ''
                [
                  "i915"
                ]
              '';
            };
          };
          stage2 = {
            kernelModules = mkOption {
              description = "Hardware specific kernel modules";
              type = types.listOf types.str;
              default = [ ];
              example = literalExpression ''
                [
                  "i915"
                ]
              '';
            };
          };
          kernelParams = mkOption {
            description = "Hardware specific kernel parameters";
            type = types.listOf types.str;
            default = [ ];
            example = literalExpression ''
              [
                "intel_iommu=on,sm_on"
                "iommu=pt"
                "module_blacklist=i915"
                "acpi_backlight=vendor"
                "acpi_osi=linux"
              ]
            '';
          };
        };
      };
    in
    {
      name = mkOption {
        description = "Name of the hardware";
        type = types.str;
        default = "";
      };

      skus = mkOption {
        description = "List of hardware SKUs (Stock Keeping Unit) covered with this definition";
        type = types.listOf types.str;
        default = [ ];
      };

      type = mkOption {
        description = "Type of hardware (laptop, desktop, server)";
        type = types.str;
        default = "laptop";
      };

      host = {
        kernelConfig = mkOption {
          description = "Host kernel configuration";
          type = kernelConfig;
          default = { };
        };

        extraVfioPciIds = mkOption {
          description = "Extra ids for the vfio-pci.ids kerenel parameter";
          type = types.listOf types.str;
          default = [ ];
        };
      };

      input = {
        keyboard = mkOption {
          description = "Name of the keyboard device(s)";
          type = inputDevSubmodule;
          default = { };
        };

        mouse = mkOption {
          description = "Name of the mouse device(s)";
          type = inputDevSubmodule;
          default = { };
        };

        touchpad = mkOption {
          description = "Name of the touchpad device(s)";
          type = inputDevSubmodule;
          default = { };
        };

        misc = mkOption {
          description = "Name of the misc device(s)";
          type = inputDevSubmodule;
          default = { };
        };
      };

      network = {
        # TODO? Should add NetVM enabler here?
        # netvm.enable = mkEnableOption = "NetVM";

        pciDevices = mkOption {
          description = "PCI Devices to passthrough to NetVM";
          type = types.listOf pciDevSubmodule;
          default = [ ];
          example = literalExpression ''
            [{
              path = "0000:00:14.3";
              vendorId = "8086";
              productId = "51f1";
            }]
          '';
        };
        kernelConfig = mkOption {
          description = "Hardware specific kernel configuration for network devices";
          type = kernelConfig;
          default = { };
        };
      };

      gpu = {
        # TODO? Should add GuiVM enabler here?
        # guivm.enable = mkEnableOption = "NetVM";

        pciDevices = mkOption {
          description = "PCI Devices to passthrough to GuiVM";
          type = types.listOf pciDevSubmodule;
          default = [ ];
          example = literalExpression ''
            [{
              path = "0000:00:02.0";
              vendorId = "8086";
              productId = "a7a1";
              qemu.deviceExtraArgs = "x-igd-opregion=on"
            }]
          '';
        };
        kernelConfig = mkOption {
          description = "Hardware specific kernel configuration for gpu devices";
          type = kernelConfig;
          default = { };
        };
      };

      audio = {
        acpiPath = mkOption {
          description = "Path to ACPI file to add to a VM";
          type = types.nullOr types.path;
          # Add ACPI table file to audioVM to enable Lenovo X1 microphone array profile
          # As we will be mostly using ACPI path for different generations of X1 so keep as default
          default = if pkgs.stdenv.hostPlatform.isx86_64 then "/sys/firmware/acpi/tables/NHLT" else null;
        };
        # With the current implementation, the whole PCI IOMMU group 14:
        #   00:1f.x in the example from Lenovo X1 Carbon
        #   must be defined for passthrough to AudioVM
        pciDevices = mkOption {
          description = "PCI Devices to passthrough to AudioVM";
          type = types.listOf pciDevSubmodule;
          default = [ ];
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
        kernelConfig = mkOption {
          description = "Hardware specific kernel configuration for audio devices";
          type = kernelConfig;
          default = { };
        };
      };

      usb = {
        devices = mkOption {
          description = ''
            Internal USB device(s) to passthrough.

            Each device definition requires a name, and either vendorId and productId, or hostbus and hostport.
            The latter is useful for addressing devices that may have different vendor and product IDs in the
            same hardware generation.

            Note that internal devices must follow the naming convention to be correctly identified
            and subsequently used. Current special names are:
              - 'cam0' for the internal cam0 device
              - 'fpr0' for the internal fingerprint reader device
          '';
          type = types.listOf usbDevSubmodule;
          default = [ ];
          example = literalExpression ''
            [
              {
                name = "cam0";
                vendorId = "0123";
                productId = "0123";
              }
              {
                name = "fpr0";
                hostbus = "3";
                hostport = "3";
              }
            ]
          '';
        };
      };

      # GUI VM hardware-specific configuration
      # These options allow hardware modules to specify VM-level configs
      # that profiles include via extendModules
      #
      # NOTE: For resource allocation (mem, vcpu), use ghaf.virtualization.vmConfig.sysvms.guivm
      guivm = {
        extraModules = mkOption {
          description = ''
            Hardware-specific NixOS modules for GUI VM configuration.
            These modules are included in the profile's extendModules call.

            Use this ONLY for hardware-specific configurations like:
            - GPU passthrough settings (PRIME, OVMF)
            - Hardware-specific QEMU arguments
            - Device-specific drivers/services

            For resource allocation (memory, vCPUs) or profile-specific modules,
            use ghaf.virtualization.vmConfig.sysvms.guivm instead.
          '';
          type = types.listOf types.unspecified;
          default = [ ];
          example = literalExpression ''
            [
              ./gpu-config.nix
              { microvm.qemu.extraArgs = [ ... ]; }
            ]
          '';
        };
      };

      # Audio VM hardware-specific configuration
      # These options allow hardware modules to specify VM-level configs
      # that profiles include via extendModules
      #
      # NOTE: For resource allocation (mem, vcpu), use ghaf.virtualization.vmConfig.sysvms.audiovm
      audiovm = {
        extraModules = mkOption {
          description = ''
            Hardware-specific NixOS modules for Audio VM configuration.
            These modules are included in the profile's extendModules call.

            Use this ONLY for hardware-specific configurations like:
            - Audio device passthrough settings
            - Hardware-specific QEMU arguments
            - Hardware detection modules

            For resource allocation (memory, vCPUs) or profile-specific modules,
            use ghaf.virtualization.vmConfig.sysvms.audiovm instead.
          '';
          type = types.listOf types.unspecified;
          default = [ ];
          example = literalExpression ''
            [
              ./audio-config.nix
              { microvm.qemu.extraArgs = [ ... ]; }
            ]
          '';
        };
      };

      netvm = {
        extraModules = mkOption {
          description = ''
            Hardware-specific NixOS modules for Net VM configuration.

            This option allows hardware definitions to provide VM-specific
            configuration that will be merged with the base Net VM config.

            Use this ONLY for hardware-specific settings like:
            - PCIe root ports configuration
            - Network device passthrough
            - Custom kernel parameters

            For resource allocation (memory, vCPUs) or profile-specific modules,
            use ghaf.virtualization.vmConfig.sysvms.netvm instead.
          '';
          type = types.listOf types.unspecified;
          default = [ ];
          example = literalExpression ''
            [
              ./net-config.nix
              { microvm.qemu.extraArgs = [ ... ]; }
            ]
          '';
        };
      };
    };
}
