<!--
    Copyright 2022-2023 TII (SSRC) and the Ghaf contributors
    SPDX-License-Identifier: CC-BY-SA-4.0
-->

# Example Project

The compartmentalization could be applied to many specific x86_64 computers and laptops with some customization applied to the Ghaf. The best way of the Ghaf customization is using Ghaf templates.

1. Create a template project as described in [Ghaf as Library](../ref_impl/ghaf-based-project.md) section
2. Adjust your system configuration with accordance to your HW specification. Determine all VIDs and PIDs of the devices that are passed to the VMs

3. Add GUIVM configuration, NetworkVM configuration and optionally some AppVMs
4. Set up weston panel shortcuts.
Refer to the existing [project example for Lenovo T14 and Lenovo X1 laptops](https://github.com/unbel13ver/ghaf-lib)

Creating the structure that includes all necessary data for the device passthrough:
```
# File 'my-hardware/lenovo-t14.nix':
# Copyright 2022-2023 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# Generic x86_64 computer -target
{
  deviceName = "lenovo-t14";
  networkPciAddr = "0000:00:14.3";
  networkPciVid = "8086";
  networkPciPid = "02f0";
  gpuPciAddr = "0000:00:02.0";
  gpuPciVid = "8086";
  gpuPciPid = "9b41";
  usbInputVid = "046d";
  usbInputPid = "c52b";
}
```
The fields of that structure are self-explanatory. Use `lspci -nnk` command to get this data from any Linux OS running on the device.
