<!--
    Copyright 2022-2023 TII (SSRC) and the Ghaf contributors
    SPDX-License-Identifier: CC-BY-SA-4.0
-->

# Compartmentalization
Compartmentalization is the technique of separating parts of a system to decrease attack surface and prevent malfunctions from cascading in the system. In Ghaf architecture, there is a separate Virtual Machine (VM) for every vital function of the system.

Current implementation supports Graphic User Interface (GUI) VM, Networking VM and a couple of Application VMs, such as Chromium web-browser and Zathura pdf reader.

The GUI VM owns computer's GPU and performs desktop environment and application windows rendering. Wayland protocol for applications in this case is proxified by `waypipe` over SSH. This approach is used temporarly before moving to more sophisticated solutions.

VM compartmentalization requires all necessary devices passthrough in place. More specifically, you need to know PCI VID and PID of a device and also it's number on the PCI bus. In case of USB device passthrough, it is enough to know device's VID and PID. See [Ghaf as Library](../ref_impl/ghaf-based-project.md) and [Creating Application VM](../ref_impl/creating_appvm.md) sections to know more about the actual implementation.