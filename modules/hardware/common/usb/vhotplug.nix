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
    getExe
    ;

  defaultRules = [
    {
      description = "Devices for GUIVM";
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
          interfaceClass = 224;
          interfaceSubclass = 1;
          interfaceProtocol = 1;
          description = "Bluetooth";
          disable = true;
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
    {
      description = "Network Devices for NetVM";
      targetVm = "net-vm";
      allow = [
        {
          interfaceClass = 2;
          interfaceSubclass = 6;
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
          description = "External Webcams for ChromeVM and BusinessVM";
          allowedVms = [
            "chrome-vm"
            "business-vm"
          ];
          allow = [
            {
              interfaceClass = 14;
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
      targetVm = "audio-vm";
      allow = [
        {
          interfaceClass = 1;
          description = "Audio";
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

  defaultVms = lib.attrsets.mapAttrsToList (vmName: vmParams: {
    name = vmName;
    type = vmParams.config.config.microvm.hypervisor;
    socket = "${config.microvm.stateDir}/${vmName}/${vmParams.config.config.microvm.socket}";
  }) config.microvm.vms;
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

      transports = lib.mkOption {
        type = lib.types.listOf (
          lib.types.enum [
            "tcp"
            "unix"
            "vsock"
          ]
        );
        default = [
          "vsock"
          "unix"
        ];
        description = ''
          List of supported transports for the API.
        '';
        example = [
          "tcp"
          "unix"
          "vsock"
        ];
      };

      allowedCids = lib.mkOption {
        type = lib.types.listOf lib.types.int;
        default =
          if config.ghaf.networking.hosts ? gui-vm then [ config.ghaf.networking.hosts.gui-vm.cid ] else [ ];
        description = ''
          List of VSOCK CIDs allowed to connect.
        '';
        example = [
          3
          4
          5
        ];
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
        disable = !cfg.enableEvdevPassthrough;
        inherit (cfg) pcieBusPrefix;
        targetVm = "gui-vm";
      };

      inherit (cfg) vms;

      general = {
        api = {
          inherit (cfg.api) enable;
          inherit (cfg.api) port;
          inherit (cfg.api) transports;
          inherit (cfg.api) allowedCids;
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
        ExecStart = "${getExe pkgs.vhotplug} -a -c /etc/vhotplug.conf";
      };
      startLimitIntervalSec = 0;
    };

    environment.systemPackages = [ pkgs.vhotplug ];
  };
}
