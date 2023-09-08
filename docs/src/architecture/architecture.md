<!--
    Copyright 2022-2023 TII (SSRC) and the Ghaf contributors
    SPDX-License-Identifier: CC-BY-SA-4.0
-->

# Architecture

The main architectural concept of the Ghaf Platform is to break up the traditional monolithic structure to modularized components, virtual machines (VM). These VMs on hardened host OS implement the Ghaf edge virtualization platform.

Embedded virtualization builds on cloud technologies in the development of end-to-end security. With hardware support for virtualization, we provide a hardened system of a small trusted computing base (TCB)—thin host—that enables isolation of use cases and their resources. Use cases are protected in guest virtual machines (VMs). Embedded targets are small devices (personal or headless) instead of high-performance cloud servers. Our scope is illustrated in the following diagram. For more information, see [stack](architecture/stack.md).

![Scope!](./../img/stack.drawio.png "Embedded Virtualization Scope")

If you are interested in why we do something *this* way instead of *that* way, see [Architecture Decision Records](adr.md).

The Ghaf Platform components are used in reference configurations to build images for reference devices. For more information, see [Reference Implementations](../ref_impl/reference_implementations.md).


## In This Chapter

- [Architectural Variants](./variants.md)
- [Architecture Decision Records](./adr.md)
  - [Minimal Host](./adr/minimal-host.md)
  - [Networking VM](./adr/netvm.md)
  - [Platform Bus for Rust VMM](./adr/platform-bus-passthrough-support.md)
- [Stack](./stack.md)