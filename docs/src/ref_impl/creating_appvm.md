<!--
    Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
    SPDX-License-Identifier: CC-BY-SA-4.0
-->

# Creating Application VM

Application VM (App VM) is a VM that improves trust in system components by isolating applications from the host OS and other applications. Virtualization with hardware-backed mechanisms provides better resource protection than traditional OS. This lets users use applications of different trust levels within the same system without compromising system security. While the VMs have overhead, it is acceptable as a result of improved security and usability that makes the application seem like it is running inside an ordinary OS.

As a result, both highly trusted applications and untrusted applications can be hosted in the same secure system when the concerns are separated in their own App VM.

To create an App VM, do the following:

1. Create the new configuration file for your VM in the [modules/reference/appvms](https://github.com/tiiuae/ghaf/tree/main/modules/reference/appvms) directory.  
   You can use an already existing VM file as a reference, for example: `modules/reference/appvms/business.nix`.

    Each VM has the following properties:

    | **Property** | **Type**                  | **Unique** | **Description**                                                                                               | **Example**         |
    | -------------- | --------------------------- | ------------ | --------------------------------------------------------------------------------------------------------------- | --------------------- |
    | name         | str                       | yes        | This name is postfixed with `-vm` and will be shown in microvm list. The name, for example, `chromium-vm` will be also the VM hostname. The length of the name must be 8 characters or less.                                     | “chromium”        |
    | packages     | list of types.package     | no         | Packages to include in a VM. It is possible to make it empty or add several packages.                          | [chromium top]    |
    | macAddress   | str                       | yes        | Needed for network configuration.                                                                              | "02:00:00:03:03:05" |
    | ramMb        | int, [1, …, host memory] | no         | Memory in MB.                                                                                                  | 3072                |
    | cores        | int,  [1, …, host cores] | no         | Virtual CPU cores.  

2. Create a new option for your VM in [modules/reference/appvms/default.nix](https://github.com/tiiuae/ghaf/blob/main/modules/reference/appvms/default.nix). For example:

```
    business-vm = lib.mkEnableOption "Enable the Business appvm";
    new-vm = lib.mkEnableOption "Enable the New appvm"; # your new vm here
```

```
        ++ (lib.optionals cfg.business-vm [(import ./business.nix {inherit pkgs lib config;})])
        ++ (lib.optionals cfg.new-vm [(import ./new_vm_name.nix {inherit pkgs lib config;})]); # your new vm here
```

3. Add your new VM to the profile file, for example [mvp-user-trial.nix](https://github.com/tiiuae/ghaf/blob/main/modules/profiles/mvp-user-trial.nix):

```
          business-vm = true;
          new-vm = true; # your new vm here
```

> [!NOTE]
> For more information on creating new profiles, see [Profiles Configuration](./profiles-config.md).

4. Add an IP and the VM name in [modules/common/networking/hosts.nix](https://github.com/tiiuae/ghaf/blob/main/modules/common/networking/hosts.nix). For example:
   
```
    {
      ip = 105;
      name = "business-vm";
    }
```

5. Add an application launcher in [modules/common/services/desktop.nix](https://github.com/tiiuae/ghaf/blob/main/modules/common/services/desktop.nix).  
  
   A launcher element has the following properties:

   * **name**: the name of the launcher;
   * **path**: path to the executable you want to run, like a graphical application;
   * **icon**: an optional icon for the launcher. If not specified, the system will attempt to find an icon matching the `name`. You can set this to the name of an icon you expect to be available in the current icon theme (currently "Papirus," defined in `modules/desktop/graphics/labwc.nix`), or provide a full path to a specific icon file.