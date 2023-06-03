<!--
    Copyright 2022-2023 TII (SSRC) and the Ghaf contributors
    SPDX-License-Identifier: CC-BY-SA-4.0
-->

# Derive a Custom Project From Ghaf

Ghaf is a framework for creating virtualized edge devices, it is therefore expected that projects wishing to use Ghaf should import it to create a derived work
for the specific use case.

Ghaf provides a number templates for the reference hardware to ease this process.

## Creating a custom derivation

1. Check the available target templates
```
    nix flake show github:tiiuae/ghaf
```
2. Select the appropriate template e.g. `target-aarch64-nvidia-orin-agx`
```
    nix flake new --template github:tiiuae/ghaf#target-aarch64-nvidia-orin-agx /my/new/project/folder
```
3. Change the placeholder `<PROJ NAME>` to your new projects name e.g. `cool_project`
```
    sed -i 's/PROJ_NAME/cool_project/g' flake.nix
```
4. Hack, test, commit, contribute back to Ghaf ;) ...
