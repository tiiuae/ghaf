# Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  lib,
  pkgs,
  config,
  ...
}: let
  cfg = config.ghaf.hardware.nvidia.passthroughs.uarti_net_vm;
in {
  options.ghaf.hardware.nvidia.passthroughs.uarti_net_vm.enable = lib.mkOption {
    type = lib.types.bool;
    default = false;
    description = "Enable UARTI passthrough on Nvidia Orin to the Net-VM";
  };

  config = lib.mkIf cfg.enable {
    services.udev.extraRules = ''
      # Make group kvm all devices that bind to vfio in iommu group 59
      SUBSYSTEM=="vfio",KERNEL=="59",GROUP="kvm"
    '';
    ghaf.hardware.nvidia.virtualization.enable = true;

    ghaf.virtualization.microvm.netvm.extraModules = [
      {
        # Use serial passthrough (ttyAMA0) and virtual PCI serial (ttyS0)
        # as Linux console
        microvm.kernelParams = [
          "console=ttyAMA0 console=ttyS0"
        ];
        microvm.qemu.serialConsole = false;
        microvm.qemu.extraArgs = [
          # Add custom dtb to Net-VM with 31d0000.serial in platform devices
          "-dtb"
          "${config.hardware.deviceTree.package}/tegra234-p3701-ghaf-net-vm.dtb"
          # Add UARTI (31d0000.serial) as passtrhough device
          "-device"
          "vfio-platform,host=31d0000.serial"
          # Add a virtual PCI serial device as console
          "-device"
          "pci-serial,chardev=stdio,id=serial0"
        ];
      }
    ];

    # Make sure that Net-VM runs after the binding services are enabled
    systemd.services."microvm@net-vm".after = ["bindSerial31d0000.service"];

    boot.kernelPatches = [
      {
        name = "Add Net-VM device tree with UARTI in platform devices";
        patch = ./patches/net_vm_dtb_with_uarti.patch;
      }
    ];

    systemd.services.bindSerial31d0000 = {
      description = "Bind UARTI to the vfio-platform driver";
      wantedBy = ["multi-user.target"];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = "yes";
        ExecStartPre = ''
          ${pkgs.bash}/bin/bash -c "echo vfio-platform > /sys/bus/platform/devices/31d0000.serial/driver_override"
        '';
        ExecStart = ''
          ${pkgs.bash}/bin/bash -c "echo 31d0000.serial > /sys/bus/platform/drivers/vfio-platform/bind"
        '';
      };
    };

    # Enable hardware.deviceTree for handle host dtb overlays
    hardware.deviceTree.enable = true;

    # Apply the device tree overlay only to tegra234-p3701-host-passthrough.dtb
    hardware.deviceTree.overlays = [
      {
        name = "uarti_pt_host_overlay";
        dtsFile = ./uarti_pt_host_overlay.dts;

        # Apply overlay only to host passthrough device tree
        # TODO: make this avaliable if PCI passthrough is disabled
        filter = "tegra234-p3701-host-passthrough.dtb";
      }
    ];
  };
}
