# Copyright 2022-2025 TII (SSRC) and the Ghaf contributors
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
    optionals
    ;

  defaultRules = [
    {
      description = "Devices for GUIVM";
      targetVm = "GUIVM";
      allow = [
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
    }
    {
      description = "Network Devices for NetVM";
      targetVm = "NetVM";
      allow = [
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
        {
          description = "Webcams for ChromeVM";
          targetVm = "ChromeVM";
          allow = [
            {
              class = 14;
              description = "Video (USB Webcams)";
            }
          ];
          deny = [
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
            {
              # Ignore System76 darp11-b camera since it is attached to the business-vm
              # Finland SKU
              vendorId = "04f2";
              productId = "b729";
              description = "System76 darp11-b Integrated Camera";
            }

          ];
        }
      ]
  ++ optionals config.ghaf.virtualization.microvm.audiovm.enable [
    {
      description = "Audio Devices for AudioVM";
      targetVm = "AudioVM";
      allow = [
        {
          class = 1;
          description = "Audio";
        }
      ];
      deny = [
        {
          class = 14;
          description = "Video (USB Webcams)";
        }
      ];
    }
  ];

  defaultVms = [
    {
      name = "GUIVM";
      type = "qemu";
      socket = "/var/lib/microvms/gui-vm/gui-vm.sock";
    }
    {
      name = "NetVM";
      type = "qemu";
      socket = "/var/lib/microvms/net-vm/net-vm.sock";
    }
    {
      name = "ChromeVM";
      type = "qemu";
      socket = "/var/lib/microvms/chrome-vm/chrome-vm.sock";
    }
    {
      name = "BusinessVM";
      type = "qemu";
      socket = "/var/lib/microvms/business-vm/business-vm.sock";
    }
    {
      name = "AudioVM";
      type = "qemu";
      socket = "/var/lib/microvms/audio-vm/audio-vm.sock";
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
        List of USB hot plugging rules.
      '';
    };

    vms = mkOption {
      type = types.listOf types.attrs;
      default = defaultVms;
      description = ''
        List of virtual machines.
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

    api = {
      enable = mkOption {
        description = ''
          Enable external API.
        '';
        type = types.bool;
        default = true;
      };

      port = lib.mkOption {
        type = lib.types.int;
        default = 2000;
        description = ''
          API port number.
        '';
      };
    };
  };

  config = mkIf cfg.enable {
    services.udev.extraRules = ''
      SUBSYSTEM=="usb", GROUP="kvm"
      KERNEL=="event*", GROUP="kvm"
    '';

    environment.etc."vhotplug.conf".text = builtins.toJSON {
      usbPassthrough = cfg.prependRules ++ cfg.rules ++ cfg.postpendRules;

      evdevPassthrough = {
        enable = cfg.enableEvdevPassthrough;
        inherit (cfg) pcieBusPrefix;
        targetVm = "GUIVM";
      };

      inherit (cfg) vms;

      general = {
        api = {
          inherit (cfg.api) enable;
          inherit (cfg.api) port;
          transport = "vsock";
        };
      };
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
