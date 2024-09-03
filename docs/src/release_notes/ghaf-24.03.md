<!--
    Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
    SPDX-License-Identifier: CC-BY-SA-4.0
-->

# Release ghaf-24.03


## Release Tag

<https://github.com/tiiuae/ghaf/releases/tag/ghaf-24.03>


## Supported Hardware

The following target hardware is supported by this release:

* NVIDIA Jetson AGX Orin
* NVIDIA Jetson Orin NX
* Generic x86 (PC)
* Polarfire Icicle Kit
* Lenovo ThinkPad X1 Carbon Gen 11
* Lenovo ThinkPad X1 Carbon Gen 10


## What is New in ghaf-24.03

* Added support for Lenovo ThinkPad X1 Carbon Gen 10.
* Lenovo X1 Carbon Gen 10/11:
  * labwc is used as a main window-stacking compositor. Weston is no longer supported.
  * [Standalone installer](https://tiiuae.github.io/ghaf/ref_impl/installer.html).
  * Hardened host and guest kernel configurations, disabled by default.
  * Power control (Power Off and Reboot).
  * Configurable border colors for application windows.
  * Initial [tpm2-pkcs11](https://layers.openembedded.org/layerindex/recipe/333608/) support.
  * Screen lock, disabled by default.
  * Minimized systemd.
* NVIDIA Jetson Orin:
  * Boot and Power Management virtualization, built as a separate target.
  * Jetpack baseline software updates and fixes.
* Further modularization of the Ghaf framework: [Ghaf as Library: Templates](../ref_impl/ghaf-based-project.md).
* Development, testing, and performance tooling improvements.


## Bug Fixes

Fixed bugs that were in the ghaf-23.12 release:

* The GALA application does not work.
* Copying text from the browser address bar to another application does not work.
* The taskbar disappears after the external display is disconnected from Lenovo X1.


## Known Issues and Limitations

| Issue           | Status      | Comments                             |
|-----------------|-------------|--------------------------------------|
| Cannot log in to the Element chat with a Google account  | In Progress | Workaround for x86: create a user specifically for Element. |
| Windows launcher application does not work on AGX  | In Progress | Workaround: launch a Windows VM from the command line. |
| Time synchronization between host and VMs does not work in all scenarios  | In Progress | Under investigation. |
| Closing and reopening a deck lid of a Lenovo ThinkPad X1 laptop with Ghaf running causes instability | In Progress | Workaround: keep a deck lid of a laptop open while working with Ghaf. |
| Applications do not open from icons when netvm is restarted | In Progress | Workaround: restart AppVMs. |
| Cannot connect to a hidden Wi-Fi network from GUI | In Progress | Workaround:  connect with SSH to a netvm and run the command: `nmcli dev wifi connect SSID password PASSWORD hidden yes`. |


## Environment Requirements

There are no specific requirements for the environment with this release.


## Installation Instructions

Released images are available at [vedenemo.dev/files/releases/ghaf_24.03/](https://vedenemo.dev/files/releases/ghaf_24.03/).

Download the required image and use the following instructions:

| Release Image           | Build and Run      |
|-------------------------|--------------------|
| ghaf-24.03_Generic_x86.tar.xz | [Running Ghaf Image for x86 Computer](../ref_impl/build_and_run.md#running-ghaf-image-for-x86-computer) |
| ghaf-24.03_Lenovo_X1_Carbon_Gen11.tar.xz  | [Running Ghaf Image for Lenovo X1](../ref_impl/build_and_run.md#running-ghaf-image-for-lenovo-x1) |
| ghaf-24.03_Nvidia_Orin_AGX_cross-compiled-no-demoapps.tar.xz[^note], ghaf-24.03_Nvidia_Orin_AGX_cross-compiled.tar.xz, ghaf-24.03_Nvidia_Orin_AGX_native-build.tar.xz | [Ghaf Image for NVIDIA Jetson Orin AGX](../ref_impl/build_and_run.md#ghaf-image-for-nvidia-jetson-orin-agx) |
| ghaf-24.03_Nvidia_Orin_NX_cross-compiled-no-demoapps[^note1].tar.xz, ghaf-24.03_Nvidia_Orin_NX_cross-compiled.tar.xz, ghaf-24.03_Nvidia_Orin_NX_native-build.tar.xz | [Ghaf Image for NVIDIA Jetson Orin AGX](../ref_impl/build_and_run.md#ghaf-image-for-nvidia-jetson-orin-agx) |
| ghaf-24.03_PolarFire_RISC-V.tar.xz | [Building Ghaf Image for Microchip Icicle Kit](../ref_impl/build_and_run.md#building-ghaf-image-for-microchip-icicle-kit) |

[^note1] no-demoapps images do not include Chromium, Zathura, and GALA applications.