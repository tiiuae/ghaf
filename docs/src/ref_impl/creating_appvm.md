<!--
    Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
    SPDX-License-Identifier: CC-BY-SA-4.0
-->

# Creating Application VM

Application VM (App VM) is a VM that improves trust in system components by isolating applications from the host OS and other applications. Virtualization with hardware-backed mechanisms provides better resource protection than traditional OS. This lets users use applications of different trust levels within the same system without compromising system security. While the VMs have overhead, it is acceptable as a result of improved security and usability that makes the application seem like it is running inside an ordinary OS.

As a result, both highly trusted applications and untrusted applications can be hosted in the same secure system when the concerns are separated in their own AppVM.

To create an App VM:
1. Add the VM description.
2. Add an application launcher in GUI VM.


## Adding App VM Description

Add the VM description in the target configuration.  
[lenovo-x1-carbon.nix](https://github.com/tiiuae/ghaf/blob/main/targets/lenovo-x1-carbon.nix) already has chromium-vm, gala-vm, and zathura-vm.

```
vms = with pkgs; [
  {
    name = "chromium";
    packages = [chromium];
    macAddress = "02:00:00:03:03:05";
    ramMb = 3072;
    cores = 4;
  }
  {
    name = "gala";
    packages = [(pkgs.callPackage ../packages/gala {})];
    macAddress = "02:00:00:03:03:06";
    ramMb = 1536;
    cores = 2;
  }
  {
    name = "zathura";
    packages = [zathura];
    macAddress = "02:00:00:03:03:07";
    ramMb = 512;
    cores = 1;
  }
];
```

Each VM has the following properties:

| **Property** | **Type**                  | **Unique** | **Description**                                                                                               | **Example**         |
| -------------- | --------------------------- | ------------ | --------------------------------------------------------------------------------------------------------------- | --------------------- |
| name         | str                       | yes        | This name is postfixed with `-vm` and will be shown in microvm list. The name, for example, `chromium-vm` will be also the VM hostname. The length of the name must be 8 characters or less.                                     | “chromium”        |
| packages     | list of types.package     | no         | Packages to include in a VM. It is possible to make it empty or add several packages.                          | [chromium top]    |
| macAddress   | str                       | yes        | Needed for network configuration.                                                                              | "02:00:00:03:03:05" |
| ramMb        | int, [1, …, host memory] | no         | Memory in MB.                                                                                                  | 3072                |
| cores        | int,  [1, …, host cores] | no         | Virtual CPU cores.                                                                                             | 4                   |


## Adding Application Launcher in GUI VM

To add an application launcher, add an element in the [guivm.nix](https://github.com/tiiuae/ghaf/blob/main/modules/microvm/virtualization/microvm/guivm.nix) file to the **graphics.weston.launchers** list.

A launcher element has two properties:

* **path**: path to the executable you want to run, like a graphical application;
* **icon**: path to an icon to show.

Check the example launchers at [guivm.nix](https://github.com/tiiuae/ghaf/blob/main/modules/microvm/virtualization/microvm/guivm.nix).
