<!--
    Copyright 2022-2023 TII (SSRC) and the Ghaf contributors
    SPDX-License-Identifier: CC-BY-SA-4.0
-->

# Ghaf as Library: Templates

Ghaf is a framework for creating virtualized edge devices, it is therefore expected that projects wishing to use Ghaf should import it to create a derived work for the specific use case.

In practise, projects should import Ghaf and its dependencies into an external version control (git) repository. Ghaf provides templates for the reference hardware to ease this process. In this section:

 * overview of Ghaf usage and upstream dependencies
 * required steps to create a Ghaf-based project
 * updating the project to get the latest changes
 * customization of the project using Ghaf-modules and Nix-supported mechanisms

Ghaf usage in your project is illustrated in the following diagram:

![Ghaf Usage Overview](../img/usage_overview.drawio.png "Your project and example inputs from Ghaf and other repositories")

The Ghaf Platform repository provides declarative modules and reference implementations to help with declaring your customized secure system.

External repositories help make various HW options, system image generators, and reference board-support packages available.


## Using Ghaf Templates

1. Check the available target templates:

    ```
    nix flake show github:tiiuae/ghaf
    ```

2. Select the appropriate template based on reference implementation, for example, `target-aarch64-nvidia-orin-agx`:

    ```
    nix flake new --template github:tiiuae/ghaf#target-aarch64-nvidia-orin-agx ~/ghaf-example
    wrote: ~/ghaf-example/flake.nix
    ```

3. See your project template outputs:
  
    ```
    cd ~/ghaf-example/
    nix flake show
    git+file://~/ghaf-example
    ├───formatter
    │   ├───aarch64-linux: package 'alejandra-3.0.0'
    │   └───x86_64-linux: package 'alejandra-3.0.0'
    ├───nixosConfigurations
    │   └───PROJ_NAME-ghaf-debug: NixOS configuration
    └───packages
    ├───aarch64-linux
    │   └───PROJ_NAME-ghaf-debug: package 'nixos-disk-image'
    └───x86_64-linux
    └───PROJ_NAME-ghaf-debug-flash-script: package 'flash-ghaf'
    ```

4. Change the placeholder `<PROJ NAME>` to the name of your project `your_project`:
  
    ```
    sed -i 's/PROJ_NAME/your_project/g' flake.nix
    ```


## Updating Ghaf Revision

To update your project, run `nix flake update`. This check the inputs for updates and based on availability of the updates, generate an updated `flake.lock` which locks the specific versions to support the reproducible builds without side effects.

In practice, nix flake will not allow floating inputs but all the inputs and declared packages must be mapped to specific hashes to get exact revisions of your inputs. This mechanism also supports the supply-chain security - if someone changes the upstream project e.g. by over-writing a part of the input so that the hash changes, you will notice. (Believe it or not, this happens even with large HW vendors). 

After update, review and testing - commit the updated `flake.lock` to your version history to share reproducible builds within your project.

## Customizing Ghaf Modules

To use the Ghaf declarative module system, check what you need in your system and choose the [modules options](./modules_options.md) you need. For example, import the ghaf `graphics`-module and declare that you won't need the reference Wayland-compositor Weston and the demo applications:

```
          {
            ghaf.graphics.weston = {
              enable = false;
              enableDemoApplications = false;
            };
          }
```
After the change, rebuild the system and switch it into use in your target device and it will run with the GUI and apps removed. After testing, you can commit the changes and share them for your colleagues to be able to build the exactly same system - even system image - as needed in your project.
