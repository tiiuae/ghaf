<!--
    Copyright 2023 TII (SSRC) and the Ghaf contributors
    SPDX-License-Identifier: CC-BY-SA-4.0
-->

# Features

Ghaf platform supports features presented in the following table.

| Feature           | Status      | Reference device | Comments/Details                             |
|-------------------|-------------|------------------|----------------------------------------------|
| Device image      | `Done`        | `Orin`  | Based on [Jetson Linux](https://developer.nvidia.com/embedded/jetson-linux), [OE4T](https://github.com/OE4T) and [jetpack-nixos](https://github.com/anduril/jetpack-nixos) |
| CI builds         | `In progress` | `Orin`  | [Only `main`-branch, not for all PRs](https://vedenemo.dev/) |
| Generic image     | `In progress` | `x86`            | NUC target - based on generic [NixOS](https://nixos.org/) |
| Device flashing   | `Done`        | `Orin`  | Full device update, `x86` via removable media |
| Native build      | `Done`        | `aarch64, x86`   |                                              |
| Emulated build    | `Regression`  | `Orin`  | `binfmt` - may freeze the build machine      |
| Cross-compilation | `In progress` | `Orin`  | Depends on NixOS `nixpkgs 22.11/23.05`       |
| Debug: SSH        | `Done`        | `Orin`, `x86` | Host access in development-mode, see [authentication](https://github.com/tiiuae/ghaf/blob/main/modules/development/authentication.nix) |
| Debug: Serial     | `Done`        | `Orin` | Host access in development-mode through debug serial |
| `minimal host`    | `In progress` | [`All variants`](https://tiiuae.github.io/ghaf/architecture/variants.html) | See [ADR](https://tiiuae.github.io/ghaf/architecture/adr/minimal-host.html) and [issue tracker](https://github.com/tiiuae/ghaf/issues/45) |
| `netvm`           | `In progress` | `Orin`  | See [ADR](https://tiiuae.github.io/ghaf/architecture/adr/netvm.html) - passthrough not working |
| USB passthrough   | `In progress` | `Orin`  | Passthrough with crosvm not verified         |
| PCI passthrough   | `In progress` | `Orin`  | WIFI passthrough verified only in development |
| UART passthrough  | `In progress` | `Orin`  | See [Nvidia AGX Orin - UART Passthrough](https://tiiuae.github.io/ghaf/build_config/passthrough/nvidia_agx_pt_uart.html) - not integrated to `netvm` |
| Inter VM comms    | `In progress` | [`All variants`](https://tiiuae.github.io/ghaf/architecture/variants.html) | |
| Shared memory     | `In progress` | `Orin` | |
| Graphics/Desktop  | `In progress` | `Orin`, `x86` | Host only graphics for now                   |
| Virtualization control | `In progress` | [`All variants`](https://tiiuae.github.io/ghaf/architecture/variants.html) | See [vmd design](https://github.com/tiiuae/vmd/blob/main/doc/design.md) | |

## Status
- `Done` - integrated and tested in the `main`-branch
- `In progress` - prototyped or work in progress in development branch
- `Regression` - feature has regression or bugs

## Reference devices
- `Orin` - NVIDIA Jetson AGX Orin - the main reference device
- `x86` - generic x86 64 - tested on Intel NUC (Next Unit of Computing) or laptop
- `aarc64` - generic aarch64 - tested on ARM server, laptop (e.g. Apple Mx) or NVIDIA Jetson AGX Orin
- `All variants` - see [details](https://tiiuae.github.io/ghaf/architecture/variants.html)
