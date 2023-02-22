<!--
    Copyright 2023 TII (SSRC) and the Ghaf contributors
    SPDX-License-Identifier: CC-BY-SA-4.0
-->

# Architectural Variants

The main scope of the Ghaf platform is edge virtualization. However, to support modular development and testing of the platform, variants are supported with following definitions:

- `Default`     - a default variant - supports [minimal host](./adr/minimal-host.md), GUI VM[^note] and [Networking VM](./adr/netvm.md). May host other VMs - see [stack](./stack.md) for more information.
- `Headless` - a variant has only [minimal host](./adr/minimal-host.md) and [Networking VM](./adr/netvm.md). May host other VMs but does not have GUI VM or graphics stack on host.
- `Host only` - a variant with [minimal host](./adr/minimal-host.md) *only*. User can manually install software to host, including virtual machines (if supported by hardware).
- `No virtualization` - a variant for hardware with no support for virtualization. May run any software, similar to popular Linux distributions, but cannot support guest virtual machines. May host any software deployed directly on host.

| Variant name       | Headless           | Graphics         | Virtual machines                  | Examples of devices  |
|---                 |---                 |---               | ---                               | ---                  |
| `Default`          | No                 | GUI VM [^note]   | Supported                         | Jetson, generic x86  |
| `Headless`         | Yes                | No               | Supported                         | Jetson, generic x86  |
| `Host Only`        | Yes                | No               | May be supported but not included | Jetson, generic x86  |
| `No Virtualization`| Yes or no          | Native on host   | Not supported                     | Raspberry Pi, RISC-V |

[^note] As of early 2023, graphics stack is deployed on host to support application development. Work is ongoing to define the GUI VM and isolate graphics with GPU passthrough.
