<!--
    Copyright 2023 TII (SSRC) and the Ghaf contributors
    SPDX-License-Identifier: CC-BY-SA-4.0
-->

# Stack

The ghaf stack includes host with virtual machines. Host has two layers: OS kernel with hypervisor and OS user space.
Host provides virtualization for the guest virtual machines: system VMs, application or service VMs or guest OSs.
The stack layers and top-level components are illustrated in the following stack diagram. The stack diagram also illustrates the scope of different layers and components with color coding.

![Stack!](../img/stack.drawio.png "Ghaf stack")

At the lowest levels of the stack lay hardware vendor provided hardware, firmware and board support package. The Ghaf project aims to use the vendor provided components either as they are or configure them as supported by the vendor. Configuration may include, for example, host kernel hardening and including only selected components from the vendor BSP.

The Ghaf project provides the reference minimal host with user space as defined in the [minimal host ADR](./adr/minimal-host.md).

## System VMs

Ghaf provides reference system virtual machines for networking, graphical user interface (GUI) and storage.

| System VM        | Defined            | Implementation status  |
|---               |---                 |---               |
| Networking       | [Yes](adr/netvm.md)| Partial          |
| GUI (optional)   | No                 | Reference Wayland on host, to be isolated to VM |

GUI VM is considered optional as it may not be needed in some headless configurations.

## Application or Service VM

Ghaf will provide reference application VMs and service VMs that isolate respective software from the host. These VMs will communicate with other parts of the system over networking and shared memory - depending on the use case requirements. As an example, application VMs (Wayland client) will communicate with the GUI VM (Wayland compositor) across the virtual machine boundaries. This is called cross-domain Wayland. Another, already partially implemented area is networking VM that will securely provide the internet access to the other VMs.

## Guest OSs

Ghaf aims to support users with guest operating systems such as other Linux distributions (Ubuntu, Fedora, etc.), Windows and Android. Some of these have been already prototyped.
