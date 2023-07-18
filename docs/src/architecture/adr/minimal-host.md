<!--
    Copyright 2022-2023 TII (SSRC) and the Ghaf contributors
    SPDX-License-Identifier: CC-BY-SA-4.0
-->

# Minimal Host

## Status

Proposed.

## Context

Ghaf uses the default NixOS configuration as a baseline to build the target image.

The default NixOS configuration is targeted for more general use with the inclusion of multiple packages that are not supporting the Ghaf design target of a minimal TCB to protect the host. Depending on the flexibility of the NixOS configuration, Ghaf minimal host may require new development to support the requirements.


This structure in the Ghaf host configuration imports the NixOS minimal profile which suits the minimal TCB better. Even better, the modular declarative profile enables the further optimization of the minimal TCB while supporting other profiles that suit the evaluation of other objectives such as feasibility studies of additional functionality,
security and performance.

## Requirements

Following table describes the development requirements of minimal host. All requirements originate from TII SSRC unless otherwise noted. Scope further defines:

* target configuration: `R` for release, `D` for debug
* [architectural variant](https://tiiuae.github.io/ghaf/architecture/variants.html): `V` for
 virtualization supporting variant, `A` for all, including `No Virtualization`

Compliance states the progress of requirement compliance as follows:

* `D` for Designed, design requirement from TII SSRC for analysis and evaluation.
* `I` for Implemented, design requirement met with possible, limitations documented
under [Consequences](#consequences).
* `P` for Proposed, raised for discussion but not yet designed.
* `M` for Met, the requirement is reviewed and approved at [technology readiness level 4](https://en.wikipedia.org/wiki/Technology_readiness_level).


| ID   | Requirement       | Description                | Scope    | Compliance |
|------|-------------------|----------------------------|----------|--------|
| MH01 | Defined in `nix`  | Host declaration in `nix`  | `R&D`,`A`| `I`    |
| MH02 | Reduced profile   | Remove unnecessary         | `R`, `V` | `I`    |
| MH03 | No networking     | Host has no networking     | `R`, `V` | `D`    |
| MH04 | No graphics       | Host has no GUI stack      | `R`, `V` | `D`    |
| MH05 | No getty          | Host has no terminal       | `R`, `V` | `P`    |
| MH06 | No nix tooling    | Only `/nix/store`, no nix  | `R`, `V` | `P`    |
| MH07 | Minimal defconfig | Host kernel is minimized   | `R`, `V` | `D`    |
| MH08 | Update via adminvm | A/B update outside host   | `R`, `V` | `P`    |
| MH09 | Read-only filesystem | Mounted RO, integrity checked | `R`, `V` |`P `|

This list of requirements is not yet comprehensive and may be changed based on findings of further analysis as stated in the following section.

## Decision

This ADR adopts a custom developed minimal profile using nixpkgs. It reduces both image and root partition size by eliminating the host OS content per requirements and implements a minimal TCB.

The current implementation of NixOS overridden. For more information on a minimal host profile, see [minimal.nix](https://github.com/tiiuae/ghaf/blob/main/modules/host/minimal.nix).

With the progress of implementing the requirements, the minimal host customization will be illustrated.

## Consequences

### Defined in `nix` (MH01)

Ghaf minimal host module is implemented in [`nix` modules](https://github.com/tiiuae/ghaf/tree/main/modules/host).
Currently, host and VM declarations are implemented using [microvm.nix](https://github.com/tiiuae/ghaf/blob/main/modules/host/microvm.nix) but this is not strict requirement for ghaf release mode declarations if the limitations or dependencies of microvm.nix do not comply with other requirements. This may require separate release mode custom nix declarations to support flexibility with microvm.nix in debug mode.

### Reduced profile (MH02)

Initial Ghaf minimal profile host size reduction [is implemented](https://github.com/tiiuae/ghaf/pull/95) with metrics on host total size and break down of size of the largest dependencies. Based on the metrics, further analysis is needed on several key modules including, but not limited to, kernel, systemd and nixos.

### No networking (MH03)

Currently ghaf host profile for both release and debug target has networking. Requirement of no networking on release target requires declarative host configuration where:
- The release target host kernel is built without networking support. Networking must be enabled for debug target.
- The release target host user space has no networking tools nor configurations. Access to tools on host must be enabled for debug target.

To support development of configuration changes between release and debug target, the debug target must support networking. This also supports `No Virtualization`-variant development in which networking must be enabled.

The exception to no networking requirement is the virtual machine manager control socket from host to guest(s). The amount of required kernel configuration dependencies and impact to different VMMs must be further analyzed.

No networking has impact on how [`vmd`](https://github.com/tiiuae/vmd/blob/main/doc/design.md) adminvm to host communication is implemented. With no networking, shared memory is proposed.

No networking may have impact on how the guest-to-guest inter virtual machine communication configuration must implemented with VMMs. This must be further analyzed.

### No graphics (MH04)

Ghaf minimal host profile for release target has no graphics. Graphics will be compartmentalized to GUIVM.
All graphics and display output related components and dependencies, including kernel drivers, must be removed from kernel configuration. Those are to be passed through to GUIVM.

### No getty (MH05)

Ghaf host in release mode must have no terminals (TTYs) to interact with. In the current state of development, this cannot be enabled yet and has minimum requirement of system logging outside the host. Proposed design to approach this is requirement is to enable getty declaratively only in a debug serial terminal under [`modules/development`](https://github.com/tiiuae/ghaf/tree/main/modules/development).

### No `nix` toolings (MH06)

Ghaf host in release mode has no nix tooling to work with the `/nix/store`. The `/nix/store` is only used to build the host system. In release mode, no modifications to nix store are possible. Changes are handled with update (MH08).

Ghaf host in debug mode must support nix tooling via read-writable host filesystem. This must be taken into account in build-time nix module declarations.

### Minimal defconfig (MH07)

Ghaf host release mode kernel configuration must be minimal and hardened in the limits of HW vendor BSP. Kernel configuration per device is to be further analyzed iteratively. Limitations are to be documented per target device kernel configurations and HW support for virtualization.

### Update via adminvm (MH08)

Ghaf host release mode filesystem updates are to be implemented using A/B update mechanism from adminvm. This will be designed and covered in a separate ADR.

### Read-only filesystem (MH09)

Ghaf minimal host in release mode must be implemented with read-only, integrity checked (`dm-verity`) filesystem. 
