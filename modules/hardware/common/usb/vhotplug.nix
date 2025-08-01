# Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.ghaf.hardware.usb.vhotplug;
  inherit (lib)
    mkEnableOption
    mkOption
    types
    mkIf
    literalExpression
    optionals
    ;

  defaultRules = [
    {
      name = "GUIVM";
      qmpSocket = "/var/lib/microvms/gui-vm/gui-vm.sock";
      usbPassthrough = [
        {
          class = 3;
          protocol = 1;
          description = "HID Keyboard";
        }
        {
          class = 3;
          protocol = 2;
          description = "HID Mouse";
        }
        {
          class = 11;
          description = "Chip/SmartCard (e.g. YubiKey)";
        }
        {
          class = 224;
          subclass = 1;
          protocol = 1;
          description = "Bluetooth";
          disable = true;
        }
        {
          class = 8;
          subclass = 6;
          description = "Mass Storage - SCSI (USB drives)";
        }
        {
          class = 17;
          description = "USB-C alternate modes supported by device";
        }
      ];
      evdevPassthrough = {
        enable = cfg.enableEvdevPassthrough;
        inherit (cfg) pcieBusPrefix;
      };
    }
    {
      name = "NetVM";
      qmpSocket = "/var/lib/microvms/net-vm/net-vm.sock";
      usbPassthrough = [
        {
          class = 2;
          subclass = 6;
          description = "Communications - Ethernet Networking";
        }
        {
          vendorId = "0b95";
          productId = "1790";
          description = "ASIX Elec. Corp. AX88179 UE306 Ethernet Adapter";
        }
      ];
    }
  ]
  ++
    optionals
      (
        config.ghaf.virtualization.microvm.appvm.enable
        && config.ghaf.virtualization.microvm.appvm.vms.chrome.enable
      )
      [
        # ChromeVM may use video devices which take precedence over audio devices / AudioVM
        {
          name = "ChromeVM";
          qmpSocket = "/var/lib/microvms/chrome-vm/chrome-vm.sock";
          usbPassthrough = [
            {
              class = 14;
              description = "Video (USB Webcams)";
              ignore = [
                {
                  # Ignore Lenovo X1 camera since it is attached to the business-vm
                  # Finland SKU
                  vendorId = "04f2";
                  productId = "b751";
                  description = "Lenovo X1 Integrated Camera";
                }
                {
                  # Ignore Lenovo X1 camera since it is attached to the business-vm
                  # Uae 1st SKU
                  vendorId = "5986";
                  productId = "2145";
                  description = "Lenovo X1 Integrated Camera";
                }
                {
                  # Ignore Lenovo X1 camera since it is attached to the business-vm
                  # UAE #2 SKU
                  vendorId = "30c9";
                  productId = "0052";
                  description = "Lenovo X1 Integrated Camera";
                }
                {
                  # Ignore Lenovo X1 gen 12 camera since it is attached to the business-vm
                  # Finland SKU
                  vendorId = "30c9";
                  productId = "005f";
                  description = "Lenovo X1 Integrated Camera";
                }
              ];
            }
          ];
        }
      ]
  ++ optionals config.ghaf.virtualization.microvm.audiovm.enable [
    {
      name = "AudioVM";
      qmpSocket = "/var/lib/microvms/audio-vm/audio-vm.sock";
      usbPassthrough = [
        {
          class = 1;
          description = "Audio";
        }
      ];
    }
  ];
in
{
  options.ghaf.hardware.usb.vhotplug = {
    enable = mkEnableOption "Enable hot plugging of USB devices";

    rules = mkOption {
      type = types.listOf types.attrs;
      default = defaultRules;
      description = ''
        List of virtual machines with USB hot plugging rules.
      '';
      example = literalExpression ''
        [
         {
            name = "GUIVM";
            qmpSocket = "/var/lib/microvms/gui-vm/gui-vm.sock";
            usbPassthrough = [
              {
                class = 3;
                protocol = 1;
                description = "HID Keyboard";
                ignore = [
                  {
                    vendorId = "046d";
                    productId = "c52b";
                    description = "Logitech, Inc. Unifying Receiver";
                  }
                ];
              }
              {
                vendorId = "067b";
                productId = "23a3";
                description = "Prolific Technology, Inc. USB-Serial Controller";
                disable = true;
              }
            ];
          }
          {
            name = "NetVM";
            qmpSocket = "/var/lib/microvms/net-vm/net-vm.sock";
            usbPassthrough = [
              {
                productName = ".*ethernet.*";
                description = "Ethernet devices";
              }
            ];
          }
        ];
      '';
    };

    prependRules = mkOption {
      description = ''
        List of extra udev rules to be added to the system. Uses the same format as vhotplug.rules,
        and is prepended to the default rules. This is helpful for setting rules where the order of
        USB device detection matters for additional VMs, while still maintaining the default rules.
      '';
      type = types.listOf types.attrs;
      default = [ ];
    };

    postpendRules = mkOption {
      description = ''
        List of extra udev rules to be added to the system. Uses the same format as vhotplug.rules,
        and is postpened to the default rules. This is useful for adding rules for additional VMs while
        keeping the ghaf defaults.
      '';
      type = types.listOf types.attrs;
      default = [ ];
    };

    enableEvdevPassthrough = mkOption {
      description = ''
        Enable passthrough of non-USB input devices on startup using QEMU virtio-input-host-pci device.
      '';
      type = types.bool;
      default = true;
    };

    pcieBusPrefix = mkOption {
      type = types.nullOr types.str;
      default = "rp";
      description = ''
        PCIe bus prefix used for the pcie-root-port QEMU device when evdev passthrough is enabled.
      '';
    };

    pciePortCount = lib.mkOption {
      type = lib.types.int;
      default = 5;
      description = ''
        The number of PCIe ports used for hot-plugging virtio-input-host-pci devices.
      '';
    };
  };

  config = mkIf cfg.enable {
    services.udev.extraRules = ''
      SUBSYSTEM=="usb", GROUP="kvm"
      KERNEL=="event*", GROUP="kvm"
    '';

    environment.etc."vhotplug.conf".text = builtins.toJSON {
      vms = cfg.prependRules ++ cfg.rules ++ cfg.postpendRules;
    };

    systemd.services.vhotplug = {
      enable = true;
      description = "vhotplug";
      wantedBy = [ "multi-user.target" ];
      after = [ "local-fs.target" ];
      serviceConfig = {
        Type = "simple";
        Restart = "always";
        RestartSec = "1";
        ExecStart = "${pkgs.vhotplug}/bin/vhotplug -a -c /etc/vhotplug.conf";
      };
      startLimitIntervalSec = 0;
    };
  };
}
