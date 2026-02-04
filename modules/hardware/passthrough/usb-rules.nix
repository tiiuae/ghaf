# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0

{ config, lib, ... }:
let
  inherit (lib)
    mkOption
    types
    mkIf
    optionals
    ;

  cfg = config.ghaf.hardware.passthrough.usb;

  defaultGuivmUsbRules = [
    {
      description = "USB Devices for GUIVM";
      targetVm = "gui-vm";
      allow = [
        {
          interfaceClass = 3;
          interfaceProtocol = 1;
          description = "HID Keyboard";
        }
        {
          interfaceClass = 3;
          interfaceProtocol = 2;
          description = "HID Mouse";
        }
        {
          interfaceClass = 11;
          description = "Chip/SmartCard (e.g. YubiKey)";
        }
        {
          interfaceClass = 8;
          interfaceSubclass = 6;
          description = "Mass Storage - SCSI (USB drives)";
        }
        {
          interfaceClass = 17;
          description = "USB-C alternate modes supported by device";
        }
      ];
    }
  ];

  defaultNetvmUsbRules = [
    {
      description = "USB Devices for NetVM";
      targetVm = "net-vm";
      allow = [
        {
          interfaceClass = 2;
          interfaceSubclass = 6;
          description = "Communications - Ethernet Networking";
        }
        {
          driverPath = ".*/kernel/drivers/net/usb/.*";
          description = "USB network devices that do not report their class or interfaces";
        }
      ];
    }
  ];

  defaultAudiovmUsbRules = [
    {
      description = "USB Devices for AudioVM";
      targetVm = "audio-vm";
      allow = [
        {
          interfaceClass = 1;
          description = "Audio";
        }
        {
          interfaceClass = 224;
          interfaceSubclass = 1;
          interfaceProtocol = 1;
          description = "Bluetooth";
        }
      ];
      deny = [
        {
          interfaceClass = 14;
          description = "Video (USB Webcams)";
        }
      ];
    }
  ];

in
{
  _file = ./usb-rules.nix;

  options.ghaf.hardware.passthrough.usb = {

    guivmRules = mkOption {
      description = "USB Device Passthrough Rules for GUIVM";
      type = types.listOf types.attrs;
      default = defaultGuivmUsbRules;
    };

    netvmRules = mkOption {
      description = "USB Device Passthrough Rules for NetVM";
      type = types.listOf types.attrs;
      default = defaultNetvmUsbRules;
    };

    audiovmRules = mkOption {
      description = "USB Device Passthrough Rules for AudioVM";
      type = types.listOf types.attrs;
      default = defaultAudiovmUsbRules;
    };
  };

  config = mkIf (config.ghaf.hardware.passthrough.mode != "none") {

    ghaf.hardware.passthrough.vhotplug.usbRules =
      optionals config.ghaf.virtualization.microvm.guivm.enable cfg.guivmRules
      ++ optionals config.ghaf.virtualization.microvm.netvm.enable cfg.netvmRules
      ++ optionals config.ghaf.virtualization.microvm.audiovm.enable cfg.audiovmRules;

  };
}
