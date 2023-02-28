<!--
    Copyright 2023 TII (SSRC) and the Ghaf contributors
    SPDX-License-Identifier: CC-BY-SA-4.0
-->

# Features

Ghaf platform supports following features:

| Feature           | Status      | Reference device | Comments/Details                             |
|-------------------|-------------|------------------|----------------------------------------------|
| Device image      | Done        | NVIDIA Orin AGX  | Based on [Jetson Linux](https://developer.nvidia.com/embedded/jetson-linux), [OE4T](https://github.com/OE4T) and [jetpack-nixos](https://github.com/anduril/jetpack-nixos) |
| Generic image     | In progress | `x86`            | NUC target - based on generic [NixOS](https://nixos.org/) |
| Device flashing   | Done        | NVIDIA Orin AGX  | Full device update, `x86` via removable media |
| Native build      | Done        | `aarch64, x86`   |                                              |
| Emulated build    | Partial     | NVIDIA Orin AGX  | `binfmt` - may freeze the build machine      |
| Cross-compilation | In progress | NVIDIA Orin AGX  | Depends on NixOS `nixpkgs 22.11/23.05`       |
| `minimal host`    | In progress | [All variants](https://tiiuae.github.io/ghaf/architecture/variants.html) | See [ADR](https://tiiuae.github.io/ghaf/architecture/adr/minimal-host.html) and [issue tracker](https://github.com/tiiuae/ghaf/issues/45) |
| `netvm`           | In progress | NVIDIA Orin AGX  | See [ADR](https://tiiuae.github.io/ghaf/architecture/adr/netvm.html) - passthrough not working |
| USB passthrough   | In progress | NVIDIA Orin AGX  | Passthrough with crosvm not verified         |
| PCI passthrough   | In progress | NVIDIA Orin AGX  | WIFI passthrough verified only in development |
| Graphics/Desktop  | In progress | NVIDIA Orin AGX and `x86` | Host only graphics for now                   |
| Virtualization control | In progress | [All variants](https://tiiuae.github.io/ghaf/architecture/variants.html) | See [vmd design](https://github.com/tiiuae/vmd/blob/main/doc/design.md) |
