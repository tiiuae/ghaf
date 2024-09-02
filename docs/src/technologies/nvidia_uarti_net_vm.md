<!--
    Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
    SPDX-License-Identifier: CC-BY-SA-4.0
-->

# NVIDIA Jetson Orin AGX: UARTI Passthrough to netvm

This document describes the UARTI (UART port I) passthrough to the netvm in Ghaf.

**NOTE**: This implementation works only with NVIDIA Jetson AGX Orin, as it is the only  NVIDIA 
Jetson Orin with the UARTI port available.

## UARTI Connection

The UARTI is mapped as *serial@31d0000* in the device tree information. This UARTI is connected to 
the NVIDIA Jetson AGX Orin Micro-USB debugging port (ttyACM1) with a default speed of 115200 bps.

For more information on the UART ports connections in NVIDIA Jetson AGX Orin, 
see: [NVIDIA Jetson AGX Orin: UART Passthrough](nvidia_agx_pt_uart.md)

## UARTI Passthrough Configuration

This section describes how the UARTI passthrough is configured in Ghaf for microvm. 
We recommend to read [NVIDIA Jetson AGX Orin: UART Passthrough](nvidia_agx_pt_uart.md) before continuing.

The UARTI passthrough configuration declaration 
[UARTI to netvm](../../../modules/reference/hardware/jetpack/nvidia-jetson-orin/virtualization/passthrough/uarti-net-vm/default.nix) 
includes:


- The microvm QEMU extra argument to add the 31d0000.serial to the netvm.
- The microvm QEMU extra argument to specify a custom device tree (dtb) for the
  netvm that includes the 31d0000.serial as a platform device.
- The microvm disable default serial console, to add virtual PCI serial console.
- A binding service (bindSerial31d0000) for the 31d0000.serial in order to 
  bind this device to the VFIO driver to make it available to microvm.
- A kernel patch to add a custom device tree (dtb) source code for the
  netvm.
- A device tree overlay to host device tree to assign an IOMMU to the 31d0000.serial 
  device, and also a dummy driver

Note: Due to the Linux kernel being unable to use the console in two UART ports 
of the same kind, a virtual PCI Serial console was used as QEMU console output.


Also, a new udev rule is defined to group all KVM devices that bind to VFIO in 
the IOMMU group 59.


    services.udev.extraRules = ''
              # Make group kvm all devices that bind to vfio in iommu group 59
              SUBSYSTEM=="vfio",KERNEL=="59",GROUP="kvm"
            '';

The *passthroughs.uarti_net_vm.enable* flag enables the UARTI passthrough to the netvm.
Make sure to enable the flag as it allows access to netvm through the debugging USB port 
when the SSH connection does not work.

	hardware.nvidia = {
		virtualization.enable = true;
		virtualization.host.bpmp.enable = false;
		passthroughs.host.uarta.enable = false;
		passthroughs.uarti_net_vm.enable = true;
	};

Enable the *virtualization.enable* flag as well, as it is a pre-requirement 
for *passthroughs.uarti_net_vm.enable*.

## Testing the UARTI on netvm

Connect the NVIDIA Jetson AGX Orin debug Micro-USB to your computer and open 
the serial port on ttyACM1 at 115200 bps. Use Picocom with the next command:

	picocom -b 115200 /dev/ttyACM1

After the netvm boots, you will see the message:

	<<< Welcome to NixOS 23.11pre-git (aarch64) - ttyAMA0 >>>

	Run 'nixos-help' for the NixOS manual.

	net-vm login: 
