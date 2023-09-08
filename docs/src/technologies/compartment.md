<!--
    Copyright 2022-2023 TII (SSRC) and the Ghaf contributors
    SPDX-License-Identifier: CC-BY-SA-4.0
-->

# Compartmentalization

Compartmentalization is the technique of separating parts of a system to decrease attack surface and prevent malfunctions from cascading in the system. In Ghaf architecture, there is a separate VM for every vital function of the system.

Current implementation supports GUI VM, [Networking VM](../architecture/adr/netvm.md) and a couple of Application VMs, such as the Chromium web browser and the Zathura document viewer.

The GUI VM owns a computer's GPU and performs desktop environment and application windows rendering. Wayland protocol for applications in this case is proxified by `waypipe` over SSH. This approach is used temporarily before moving to more sophisticated solutions.

A VM compartmentalization requires all necessary devices passthrough in place. More specifically, you need to know the PCI VID and PID of a device and also its number on the PCI bus. In the case of a USB device passthrough, it is enough to know the device's VID and PID.

For more information on actual implementation, see [Ghaf as Library](../ref_impl/ghaf-based-project.md) and [Creating Application VM](../ref_impl/creating_appvm.md).