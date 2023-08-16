<!--
    Copyright 2022-2023 TII (SSRC) and the Ghaf contributors
    SPDX-License-Identifier: CC-BY-SA-4.0
-->

# How to add a new AppVM in Ghaf

## What is AppVM?

AppVM is a virtual machine, which isolates an application from a host OS. An application seems like it is running inside an ordinary OS, yet it runs in a completely different system. An application inside renders, shows and controls from a host OS via GUI VM, network access is provided by NetVM.

In the perfect scenario, one application -- one AppVM. But it is possible to run multiple applications inside one AppVM.


## How to add a new AppVM

### 1. Add in the target

Add a new AppVM in the target file targets directory.

[generic-x86_64.nix](../../../targets/generic-x86_64.nix) already has AppVMs inside for Chromium, Gala, and Zathura applications.

#### Example of the current AppVMs

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
| name         | str                       | yes        | This name will be shown in microvm list, a VM will have the same hostname                                     | “chromium”        |
| packages     | list of types.package     | no         | Packages to include in a VM. It’s possible to make it empty or add several packages                          | [chromium top]    |
| ipAddress    | str                       | yes        | This IP will be used to access a VM from the host. Should has the same subnetwork, as other VMs: Net, GUI VMs | "192.168.101.5/24"  |
| macAddress   | str                       | yes        | Needed for network configuration                                                                              | "02:00:00:03:03:05" |
| ramMb        | int, [1, …, host memory] | no         | Memory in MB                                                                                                  | 3072                |
| cores        | int,  [1, …, host cores] | no         | Virtual CPU cores                                                                                             | 4                   |


### 2. Add an app launcher in GUI VM

To add an app launcher, add an element in the [guivm.nix](../../../modules/virtualization/microvm/guivm.nix) file to the **graphics.weston.launchers** list.
A launcher element has 2 properties:

1. **path** – at the moment, we launch an app via **waypipe** . In general, the path string will be as follows: "\${pkgs.waypipe}/bin/waypipe ssh -i ${waypipe-ssh}/keys/waypipe-ssh -o StrictHostKeyChecking=no **vm.ipAddress** **vm.executable**", where:
   **vm.ipAddress** – ipAddress you have defined in the target’s AppVM configuration,
   **vm.executable** – an executable you want to execute, like a graphical application.
2. **icon** – path to an icon to show.


#### Example of the current launchers

```
graphics.weston.launchers = [
  {
    path = "${pkgs.waypipe}/bin/waypipe ssh -i ${waypipe-ssh}/keys/waypipe-ssh -o StrictHostKeyChecking=no 192.168.101.6 gala --enable-features=UseOzonePlatform --ozone-platform=wayland";
    icon = "${pkgs.weston}/share/weston/icon_editor.png";
  }

  {
    path = "${pkgs.waypipe}/bin/waypipe ssh -i ${waypipe-ssh}/keys/waypipe-ssh -o StrictHostKeyChecking=no 192.168.101.7 zathura";
    icon = "${pkgs.weston}/share/weston/icon_editor.png";
  }
];
```
