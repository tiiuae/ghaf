<!--
    Copyright 2022-2023 TII (SSRC) and the Ghaf contributors
    SPDX-License-Identifier: CC-BY-SA-4.0
-->

# Creating Application VM

Application VM (AppVM) is a VM that improves trust in system components by isolating applications from the host OS and other applications. Virtualization with hardware-backed mechanisms provides better resource protection than traditional OS. This lets users use applications of different trust levels within the same system without compromising system security. While the VMs have overhead, it is acceptable as a result of improved security and usability that makes the application seem like it is running inside an ordinary OS.

As a result, both highly trusted applications and untrusted applications can be hosted in the same secure system when the concerns are separated in their own AppVMs.

To create an AppVM:
1. Add AppVM description.
2. Add an app launcher in GUI VM.


## Adding AppVM Description

Add the VM description in the target configuration.

[lenovo-x1.nix](../../../targets/lenovo-x1.nix) already has AppVMs inside for Chromium, Gala, and Zathura applications.


#### AppVMs Example

```
vms = with pkgs; [
  {
    name = "chromium";
    packages = [chromium];
    ipAddress = "192.168.101.5/24";
    macAddress = "02:00:00:03:03:05";
    ramMb = 3072;
    cores = 4;
  }
  {
    name = "gala";
    packages = [(pkgs.callPackage ../user-apps/gala {})];
    ipAddress = "192.168.101.6/24";
    macAddress = "02:00:00:03:03:06";
    ramMb = 1536;
    cores = 2;
  }
  {
    name = "zathura";
    packages = [zathura];
    ipAddress = "192.168.101.7/24";
    macAddress = "02:00:00:03:03:07";
    ramMb = 512;
    cores = 1;
  }
];
```

Each VM has the following properties:


| **Property** | **Type**                  | **Unique** | **Description**                                                                                               | **Example**         |
| -------------- | --------------------------- | ------------ | --------------------------------------------------------------------------------------------------------------- | --------------------- |
| name         | str                       | yes        | This name is prefixed with `vm-` and will be shown in microvm list. The prefixed name - e.g. `vm-chromium` will be also the VM hostname.                                     | “chromium”        |
| packages     | list of types.package     | no         | Packages to include in a VM. It is possible to make it empty or add several packages.                          | [chromium top]    |
| ipAddress    | str                       | yes        | This IP will be used to access a VM from the host. Should has the same subnetwork, as other VMs: Net, GUI VMs. | "192.168.101.5/24"  |
| macAddress   | str                       | yes        | Needed for network configuration.                                                                              | "02:00:00:03:03:05" |
| ramMb        | int, [1, …, host memory] | no         | Memory in MB.                                                                                                  | 3072                |
| cores        | int,  [1, …, host cores] | no         | Virtual CPU cores.                                                                                             | 4                   |


## Adding Application Launcher in GUI VM

To add an app launcher, add an element in the [guivm.nix](../../../modules/virtualization/microvm/guivm.nix) file to the **graphics.weston.launchers** list.

A launcher element has 2 properties:

1. **path** – path to the executable you want to run, like a graphical application.
2. **icon** – path to an icon to show.

Check the example launchers at [guivm.nix](../../../modules/virtualization/microvm/guivm.nix).