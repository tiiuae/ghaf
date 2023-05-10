<!--
    Copyright 2023 TII (SSRC) and the Ghaf contributors
    SPDX-License-Identifier: CC-BY-SA-4.0
-->

# Features

The vision for the Ghaf platform is to create a virtualized, scalable reference platform that enables the building of secure products leveraging trusted, reusable, and portable software for edge devices. For more information on reference implementation for several devices, see [Reference Implementations](../ref_impl/reference_implementations.md).

The following table provides the Ghaf Platform capabilities:

| Feature           | Status      | Reference Device | Details                             |
|-------------------|-------------|------------------|----------------------------------------------|
| Device image      | `Done`        | `Orin`  | Based on [Jetson Linux](https://developer.nvidia.com/embedded/jetson-linux), [OE4T](https://github.com/OE4T) and [jetpack-nixos](https://github.com/anduril/jetpack-nixos). |
| CI builds         | `In progress` | `Orin`  | [Only `main`-branch, not for all PRs](https://vedenemo.dev/). |
| Generic image     | `Done` | `x86`   | Generic x86 computer, based on generic [NixOS](https://nixos.org/). |
| Device flashing   | `Done`        | `Orin`  | Full device update, `x86` via removable media. |
| Native build      | `Done`        | `aarch64, x86`   |                                              |
| Emulated build    | `Regression`  | `Orin`  | `binfmt`, may freeze the build machine.      |
| Cross-compilation | `In progress` | `Orin`  | Depends on NixOS `nixpkgs 22.11/23.05`.       |
| Debug: SSH        | `Done`        | `Orin`, `x86` | Host access in development mode, see [authentication.nix](https://github.com/tiiuae/ghaf/blob/main/modules/development/authentication.nix). |
| Debug: Serial     | `Done`        | `Orin` | Host access in development mode through debug serial. |
| `minimal host`    | `In progress` | [`All`](https://tiiuae.github.io/ghaf/architecture/variants.html) | See [Minimal Host](https://tiiuae.github.io/ghaf/architecture/adr/minimal-host.html) and [issue #45](https://github.com/tiiuae/ghaf/issues/45). |
| `netvm`           | `In progress` | `Orin`  | See [netvm](https://tiiuae.github.io/ghaf/architecture/adr/netvm.html). Passthrough is not working. |
| USB passthrough   | `In progress` | `Orin`  | Passthrough with crosvm is not verified.         |
| PCI passthrough   | `In progress` | `Orin`  | Wi-Fi passthrough is verified only in development. |
| UART passthrough  | `In progress` | `Orin`  | See [NVIDIA Jetson AGX Orin: UART Passthrough](https://tiiuae.github.io/ghaf/build_config/passthrough/nvidia_agx_pt_uart.html). Not integrated to `netvm`. |
| Inter VM comms    | `In progress` | [`All`](https://tiiuae.github.io/ghaf/architecture/variants.html) | |
| Shared memory     | `In progress` | `Orin` | |
| Graphics/Desktop  | `In progress` | `Orin`, `x86` | Host-only graphics for now.                   |
| Virtualization control | `In progress` | [`All`](https://tiiuae.github.io/ghaf/architecture/variants.html) | See [vmd design](https://github.com/tiiuae/vmd/blob/main/doc/design.md). | |


## Status

* `Done`—integrated and tested in the `main` branch.
* `In progress`—prototyped or work in progress in the development branch.
* `Regression`—the feature has regression or bugs.


## Reference Devices

- `Orin`—NVIDIA Jetson AGX Orin as the main reference device.
- `x86`—generic x86_64; tested on Intel NUC (Next Unit of Computing) or laptop.
- `aarch64`—generic AArch64; tested on an ARM server, laptop (e.g. Apple M's), or NVIDIA Jetson AGX Orin.
- `All variants`—supported devices from [Architectural Variants](https://tiiuae.github.io/ghaf/architecture/variants.html).
