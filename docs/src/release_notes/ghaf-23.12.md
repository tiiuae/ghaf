<!--
    Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
    SPDX-License-Identifier: CC-BY-SA-4.0
-->

# Release ghaf-23.12


## Release Branch

<https://github.com/tiiuae/ghaf/tree/ghaf-23.12>


## Supported Hardware

The following target hardware is supported by this release:

* NVIDIA Jetson AGX Orin
* NVIDIA Jetson Orin NX
* Generic x86 (PC)
* Polarfire Icicle Kit
* Lenovo ThinkPad X1 Carbon Gen 11


## What is New in ghaf-23.12

* NixOS update to 23.11: [NixOS 23.11 released!](https://discourse.nixos.org/t/nixos-23-11-released/36210)
* Further modularization of the Ghaf framework: [Ghaf as Library: Templates](../ref_impl/ghaf-based-project.md).
* CLI-based installer.
* Lenovo X1 Carbon Gen 11:
  * Configurable PCI and USB devices passthrough.
  * Network Manager: support from GUI VM to Net VM.
  * Windows VM support.
  * Added Ghaf icons and the background image.
  * Secure Boot is disabled by default.
  * The hardened host kernel baseline is disabled by default.
  * Initial hardened hypervisor integration is disabled by default.
* NVIDIA Jetson Orin:
  * Configurable PCI passthrough.
  * Jetpack baseline software updates and fixes.
  * Initial OP-TEE and TEE Proxy support.
* Cross-compilation of the ARM targets (NVIDIA) on the x86 server.
* SLSA v1.0 level 2 compatible build.
* Development, testing, and performance tooling improvements.


## Bug Fixes

Fixed bugs that were in the ghaf-23.09 release:

* Chromium AppVM does not boot up on X1.
* Shutdown or reboot of Lenovo X1 takes a lot of time (7 minutes).
* Copy and paste text from or to Chromium AppVM does not work. Copy text from the address bar does not work as well.
* Personal security keys cannot be created.
* Cannot move the Element window by dragging with the mouse.


## Known Issues and Limitations

| Issue           | Status      | Comments                             |
|-----------------|-------------|--------------------------------------|
| The GALA application does not work | In Progress | Will be fixed in the next release. |
| Cannot log in to the Element chat with a Google account  | In Progress | Workaround for x86: create a user specifically for Element. |
| Copying text from the browser address bar to another application does not work  | In Progress | Under investigation. |
| Windows launcher application does not work on NUC and AGX  | In Progress | Workaround: launch a Windows VM from the command line. |
| Time synchronization between host and VMs does not work in all scenarios  | In Progress | Under investigation. |
| The taskbar disappears after the external display is disconnected from Lenovo X1  | In Progress | Under investigation. |
| Closing and re-opening a deck lid of a X1 laptop with running Ghaf causes instability | In Progress | Workaround: keep a deck lid of a laptop open while working with Ghaf. |
| Applications do not open from icons when net-vm is restarted | In Progress | Workaround: Restart App VMs. |


## Environment Requirements

There are no specific requirements for the environment with this release.


## Installation Instructions

Released images are available at [archive.vedenemo.dev/ghaf-23.12](https://archive.vedenemo.dev/ghaf-23.12/).

Download the required image and use the following instructions:

| Release Image           | Build and Run      |
|-------------------------|--------------------|
| ghaf-23.12_Generic_x86.tar.xz | [Running Ghaf Image for x86 Computer](../ref_impl/build_and_run.md#running-ghaf-image-for-x86-computer) |
| ghaf-23.12_Lenovo_X1_Carbon_Gen11.tar.xz  | [Running Ghaf Image for Lenovo X1](../ref_impl/build_and_run.md#running-ghaf-image-for-lenovo-x1) |
| ghaf-23.12_Nvidia_Orin_AGX_cross-compiled-no-demoapps.tar.xz[^note1], ghaf-23.12_Nvidia_Orin_AGX_cross-compiled.tar.xz, ghaf-23.12_Nvidia_Orin_AGX_native-build.tar.xz | [Ghaf Image for NVIDIA Jetson Orin AGX](../ref_impl/build_and_run.md#ghaf-image-for-nvidia-jetson-orin-agx) |
| ghaf-23.12_Nvidia_Orin_NX_cross-compiled-no-demoapps[^note1].tar.xz, ghaf-23.12_Nvidia_Orin_NX_cross-compiled.tar.xz, ghaf-23.12_Nvidia_Orin_NX_native-build.tar.xz | [Ghaf Image for NVIDIA Jetson Orin AGX](../ref_impl/build_and_run.md#ghaf-image-for-nvidia-jetson-orin-agx) |
| ghaf-23.12_PolarFire_RISC-V.tar.xz | [Building Ghaf Image for Microchip Icicle Kit](../ref_impl/build_and_run.md#building-ghaf-image-for-microchip-icicle-kit) |

[^note1]: no-demoapps images do not include Chromium, Zathura, and GALA applications.
