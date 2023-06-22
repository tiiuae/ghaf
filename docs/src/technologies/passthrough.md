<!--
    Copyright 2022-2023 TII (SSRC) and the Ghaf contributors
    SPDX-License-Identifier: CC-BY-SA-4.0
-->

# Devices Passthrough

Devices passthrough to virtual machines (VM) allows us to isolate the device drivers 
and their memory access in one or several VMs. This reduces the Trusted Code Base (TCB) in the host, due to the passed-through device drivers can be removed completely from the host kernel.

Whether the device platform is x86 or ARM, the passthrough device needs to be bound to the VFIO device driver by the host system before it can be passed through to the guest environment. For more information, see [Binding Device to VFIO Driver](vfio.md).


Our current supported passthrough devices implementations:
- [NVIDIA Jetson AGX Orin: UART Passthrough](nvidia_agx_pt_uart.md)
- [NVIDIA Jetson AGX Orin: PCIe Passthrough](nvidia_agx_pt_pcie.md)
- [Generic x86: PCIe Passthrough on crosvm](x86_pcie_crosvm.md)
