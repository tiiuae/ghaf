<!--
    Copyright 2024 TII (SSRC) and the Ghaf contributors
    SPDX-License-Identifier: CC-BY-SA-4.0
-->

# Architectural Variants

The main scope of the Ghaf platform is edge virtualization. However, to support modular development and testing of the platform, variants are supported with the following definitions:

* `Default`  
    A default variant. Supports [minimal host](./adr/minimal-host.md), GUI VM[^note] and [netvm](./adr/netvm.md). May host other VMs. For more information, see [Stack](./stack.md).

* `Headless`  
    A variant with [minimal host](./adr/minimal-host.md) and [netvm](./adr/netvm.md). May host other VMs but does not have GUI VM or graphics stack on a host.

* `Host only`
    A variant with [minimal host](./adr/minimal-host.md) *only*. A user can manually install software to a host, including VMs (if supported by hardware).

* `No virtualization`
    A variant for hardware with no support for virtualization. May run any software, similar to popular Linux distributions, but cannot support guest virtual machines. May host any software deployed directly on a host.


| Variant Name       | Headless           | Graphics         | VMs                               | Devices  |
|---                 |---                 |---               | ---                               | ---                  |
| `Default`          | No                 | GUI VM [^note]   | Supported                         | Jetson, generic x86  |
| `Headless`         | Yes                | No               | Supported                         | Jetson, generic x86  |
| `Host Only`        | Yes                | No               | May be supported but not included | Jetson, generic x86  |
| `No Virtualization`| Yes or no          | Native on host   | Not supported                     | Raspberry Pi, RISC-V |

[^note] As of early 2023, the graphics stack is deployed on a host to support application development. Work is ongoing to define the GUI VM and isolate graphics with GPU passthrough.
