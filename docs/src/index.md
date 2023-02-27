<!--
    Copyright 2022-2023 TII (SSRC) and the Ghaf contributors
    SPDX-License-Identifier: CC-BY-SA-4.0
-->

# TII SSRC Secure Technologies: Ghaf Framework

_[Ghaf](./appendices/glossary.md#ghaf) Framework_ is an open-source project that provides information about our work and studies in the security technologies field in the context of embedded virtualization.

The applied software research supports _[Secure Systems Research Center](./appendices/glossary.md#ssrc)_ focus areas.

## Embedded Virtualization

Embedded virtualization builds on cloud technologies in the development of end-to-end security. With hardware support for virtualization, we provide a hardened system of a small _[trusted computing base (TCB)](./appendices/glossary.md#tcb)_ — thin host — that enables isolation of use cases and their resources. Use cases are protected in guest virtual machines (VMs). Embedded targets are small devices (personal or headless) instead of high-performance cloud servers. Our scope is illustrated in the following diagram. For more information, see [stack](architecture/stack.md).

![Scope!](img/stack.drawio.png "Embedded Virtualization Scope")

## Reference Implementation

Ghaf is developing a reference implementation for NVIDIA Jetson devices.
Ghaf also supports NXP's i.MX8QuadMax-MEK development board along with generic-x86 devices. See [build instructions](build_config/reference_implementations.md) for more info.
