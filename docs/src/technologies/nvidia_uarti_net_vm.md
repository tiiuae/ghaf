<!--
    Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
    SPDX-License-Identifier: CC-BY-SA-4.0
-->

# NVIDIA Jetson: UARTI Passthrough to Net-VM

This document describes the UARTI (UART port I) passthrough to the Net-VM in Ghaf.

## UARTI Connection

The UARTI is mapped as *serial@31d0000* in the device tree information. This UARTI is connected to 
the Nvidia Jetson Orin AGX micro USB debugging port (ttyACM1) with a default speed of 115200 bps.

For more information about the UART ports connections in Nvidia Jetson Orin AGX, please 
go to: [NVIDIA Jetson AGX Orin: UART Passthrough](nvidia_agx_pt_uart.md)

## UARTI Passthrough configuration

This section describes how the UARTI passthrough is configured in Ghaf for Microvm. 
It is recommended that you read firs [NVIDIA Jetson AGX Orin: UART Passthrough](nvidia_agx_pt_uart.md) before continue.

The UARTI passthrough configuration declaration is available in: 
[UARTI to Net-VM](../../../modules/hardware/nvidia-jetson-orin/virtualization/passthrough/uarti-net-vm/default.nix) 

This declaration includes:

- Microvm Qemu extra argument to add the 31d0000.serial to the Net-VM.
- Microvm Qemu extra argument to specify a custom device tree (dtb) for the
  Net-VM that includes the 31d0000.serial as a platform device.
- Microvm disable default serial console, to add virtual pci-serial console.
- Binding service (bindSerial31d0000) for the 31d0000.serial in order to 
  bind this device to the VFIO driver to make it available to Microvm.
- Kernel patch for the host device tree, to assign an IOMMU to the 31d0000.serial 
  device, and also a dummy driver.
- Kernel patch to add a custom device tree (dtb) source code for the
  Net-VM.

Note: due the Linux kernel is not able to use the console in two UART ports
of the same kind, a virtual pci-serial console was used as qemu console output.


Also, a new udev rule was defined to make group kvm all devices that bind to vfio 
in iommu group 59.


    services.udev.extraRules = ''
              # Make group kvm all devices that bind to vfio in iommu group 59
              SUBSYSTEM=="vfio",KERNEL=="59",GROUP="kvm"
            '';

Here the *passthroughs.uarti_net_vm.enable* is enabled by default. This flag
enables the UARTI passthrough to he Net-VM. We recommend to have this enabled by 
default, because it is useful to have access to the Net-VM through the debugging
USB port when the ssh connection does not work.

	hardware.nvidia = {
		virtualization.enable = true;
		virtualization.host.bpmp.enable = false;
		passthroughs.host.uarta.enable = false;
		passthroughs.uarti_net_vm.enable = true;
	};

The flag *virtualization.enable* should be enabled, because it is a 
pre-requirement for *passthroughs.uarti_net_vm.enable*.

## Testing the UARTI on Net-VM

Connect the NVIDIA Jetson Orin (AGX/NX) debug micro USB to your PC 
and open the serial port on ttyACM1 at 115200 bps. 
You can use picocom with the next command:

	picocom -b 115200 /dev/ttyACM1

After the netvm boots you will see the next prompt: 

	<<< Welcome to NixOS 23.11pre-git (aarch64) - ttyAMA0 >>>

	Run 'nixos-help' for the NixOS manual.

	net-vm login: 
