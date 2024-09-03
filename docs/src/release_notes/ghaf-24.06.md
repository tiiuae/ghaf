<!--
    Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
    SPDX-License-Identifier: CC-BY-SA-4.0
-->

# Release ghaf-24.06


## Release Tag

<https://github.com/tiiuae/ghaf/releases/tag/ghaf-24.06>


## Supported Hardware

The following target hardware is supported by this release:

* NVIDIA Jetson AGX Orin
* NVIDIA Jetson Orin NX
* Generic x86 (PC)
* Polarfire Icicle Kit
* Lenovo ThinkPad X1 Carbon Gen 11
* Lenovo ThinkPad X1 Carbon Gen 10
* NXP i.MX 8M Plus


## What is New in ghaf-24.06

* Added support for NXP i.MX 8M Plus.
* NixOS is updated to [NixOS 24.05](https://nixos.org/blog/announcements/2024/nixos-2405/) further to nixos-unstable.
* labwc is used as a default compositor on all platforms. Weston is no longer supported.
* Static networking with external DNS server support only. Internal DHCP and DNS are removed.
  * This affects all new guest VM networking.
  * Windows VM must be configured with static IP and DNS.
* Lenovo X1 Carbon Gen 10/11:
  * Image compression uses the [Zstandard (zstd)](https://github.com/facebook/zstd) algorithm.
  * Initial vTPM implementation for Application VMs is added.
  * Audio VM with [PipeWire](https://gitlab.freedesktop.org/pipewire/pipewire) backend and [PulseAudio](https://www.freedesktop.org/wiki/Software/PulseAudio/) TCP remote communications layer.
  * Multimedia function key passthrough.
  * Initial implementation of [IDS VM](../architecture/adr/idsvm.md) as a defensive network mechanism.
  * Support for [Element](https://element.io/) chat application.
  * GPS location sharing through the Element application.
  * [AppFlowy](https://github.com/AppFlowy-IO/AppFlowy) uses the [Flutter](https://github.com/flutter) application framework.
* NVIDIA Jetson Orin NX:
  * UARTI passthrough.
  * The Jetpack baseline software updates and fixes.
* Further refactoring and modularization of Ghaf Framework.
* Development, testing, and performance tooling improvements.


## Bug Fixes

Fixed bugs that were in the ghaf-24.03 release:

* Icons do not launch applications when a netvm is restarted.
* Closing and reopening a deck lid of a Lenovo ThinkPad X1 laptop with Ghaf running causes instability.


## Known Issues and Limitations

| Issue           | Status      | Comments                             |
|-----------------|-------------|--------------------------------------|
| Cannot log in to the Element chat with a Google account  | In Progress | Workaround for x86: create a user specifically for Element. |
| Windows launcher application does not work on AGX  | In Progress | Workaround: launch a Windows VM from the command line. |
| Time synchronization between host and VMs does not work in all scenarios  | In Progress | Under investigation. |
| Applications do not open from icons when netvm is restarted | In Progress | Workaround: restart AppVMs. |
| Cannot connect to a hidden Wi-Fi network from GUI | In Progress | Workaround:  connect with SSH to a netvm and run the command: `nmcli dev wifi connect SSID password PASSWORD hidden yes`. |
| NVIDIA Jetson AGX Orin and NVIDIA Jetson Orin NX: cannot make voice calls using the Element application | In Progress | Under investigation. |
| The Element application cannot find a camera | In Progress | Under investigation. |


## Environment Requirements

There are no specific requirements for the environment with this release.


## Installation Instructions

Released images are available at [vedenemo.dev/files/releases/ghaf_24.06/](https://vedenemo.dev/files/releases/ghaf_24.06/).

Download the required image and use the following instructions:

| Release Image           | Build and Run      |
|-------------------------|--------------------|
| ghaf-24.06_Generic_x86.tar.xz | [Running Ghaf Image for x86 Computer](../ref_impl/build_and_run.md#running-ghaf-image-for-x86-computer) |
| ghaf-24.06_Lenovo_X1_Carbon_Gen11.tar.xz  | [Running Ghaf Image for Lenovo X1](../ref_impl/build_and_run.md#running-ghaf-image-for-lenovo-x1) |
| ghaf-24.06_Nvidia_Orin_AGX_cross-compiled.tar.xz, ghaf-24.06_Nvidia_Orin_AGX_native-build.tar.xz, ghaf-24.06_Nvidia_Orin_NX_cross-compiled.tar.xz, ghaf-24.06_Nvidia_Orin_NX_native-build.tar.xz  | [Ghaf Image for NVIDIA Jetson Orin AGX](../ref_impl/build_and_run.md#ghaf-image-for-nvidia-jetson-orin-agx) |
| ghaf-24.06_PolarFire_RISC-V.tar.xz | [Building Ghaf Image for Microchip Icicle Kit](../ref_impl/build_and_run.md#building-ghaf-image-for-microchip-icicle-kit) |


<!--
    There is no image for NXP i.MX 8M Plus. We say that we added the nxp support in this release but there is no image to try it. Yes, this is dog.
-->
