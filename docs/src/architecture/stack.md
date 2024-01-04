<!--
    Copyright 2024 TII (SSRC) and the Ghaf contributors
    SPDX-License-Identifier: CC-BY-SA-4.0
-->

# Stack

The Ghaf stack includes a host with VMs. The host consists of two layers—OS kernel with hypervisor and OS user space—and provides virtualization for the guest VMs: system VMs, application or service VMs, or guest OSs.
The stack layers and top-level components are illustrated in the following diagram.

![Stack!](../img/stack.drawio.png "Ghaf Stack")

At the lowest levels of the stack lay hardware vendor-provided hardware, firmware, and board support package. The Ghaf project aims to use the vendor-provided components either as they are or configure them as supported by the vendor. Configuration may include, for example, host kernel hardening and including only selected components from the vendor BSP.

The Ghaf project provides the reference minimal host with user space as defined in the [Minimal Host](./adr/minimal-host.md).

## System VMs

Ghaf provides reference system VMs for networking, GUI and storage.

| System VM        | Defined            | Implementation Status  |
|---               |---                 |---               |
| Networking       | [Yes](adr/netvm.md)| Partial          |
| GUI (optional)   | No                 | Reference Wayland on host, to be isolated to VM |

GUI VM is considered optional as it may not be needed in some headless configurations.

## Application or Service VM

Ghaf should provide reference application VMs and service VMs that isolate respective software from the host. Depending on the use case requirements, these VMs will communicate with other parts of the system over networking and shared memory. As an example, application VMs (Wayland client) will communicate with the GUI VM (Wayland compositor) across the VM boundaries. This is called cross-domain Wayland. Another, already partially implemented area is networking VM that will securely provide Internet access to other VMs.

## Guest OSs

Ghaf aims to support users with guest OSs such as other Linux distributions (Ubuntu, Fedora, etc.), Windows, and Android. Some of these have been already prototyped.
