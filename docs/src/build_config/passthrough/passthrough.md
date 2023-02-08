# Devices Passthrough

Devices passthrough to virtual machines (VM) allows us to isolate the device drivers 
and their memory access in one or several VMs. This reduces the Trusted Code Base (TCB) in the host, due to the passed-through device drivers can be removed completely
from the host kernel.

Our current supported passthrough devices implementations:
- [Nvidia AGX Orin - UART Passthrough](nvidia_agx_pt_uart.md)