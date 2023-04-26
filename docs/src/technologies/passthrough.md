<!--
    Copyright 2022-2023 TII (SSRC) and the Ghaf contributors
    SPDX-License-Identifier: CC-BY-SA-4.0
-->

# Devices Passthrough

Devices passthrough to virtual machines (VM) allows us to isolate the device drivers 
and their memory access in one or several VMs. This reduces the Trusted Code Base (TCB) in the host, due to the passed-through device drivers can be removed completely
from the host kernel.

Our current supported passthrough devices implementations:
- [Nvidia AGX Orin - UART Passthrough](nvidia_agx_pt_uart.md)
- [Nvidia AGX Orin - PCIe Passthrough](nvidia_agx_pt_pcie.md)