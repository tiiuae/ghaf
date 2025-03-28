<!--
    Copyright 2022-2025 TII (SSRC) and the Ghaf contributors
    SPDX-License-Identifier: CC-BY-SA-4.0
-->

# Release ghaf-25.03

This is a quarterly release which has been fully tested on Nvidia Orin NX, Nvidia Orin AGX and Lenovo X1 Carbon Gen11 platforms. This release complies with SLSA v1.0 level 3 requirements.



## Release Tag

https://github.com/tiiuae/ghaf/releases/tag/ghaf-25.03

## Supported Hardware

The following target hardware is supported by this release:

* NVIDIA Jetson AGX Orin
* NVIDIA Jetson Orin NX
* Lenovo ThinkPad X1 Carbon Gen 10, 11, 12
* Dell Latitude 7230, 7330
* Alienware M18 
* Generic x86 (PC)
* NXP i.MX 8M Plus

## What is New in ghaf-24.12.4

Main changes since ghaf-24.12:

* General refactoring and modularization to make Ghaf easy to consume by downstream projects.
* Major updates on upstream dependencies.
* More robust user account management.
* RISC-V Polarfire Icicle Kit builds are currently disabled but can be re-enabled if needed.
* Support for Alienware M18 laptop added.
* Added support for Lenovo ThinkPad X1 Carbon Gen 12.

Lenovo X1 Carbon Gen 10/11:

* Audio device selection and microphone slider are added to the quick settings widget.
* Audio control was removed from the application menu.
* TLS enabled for GIVC.
* Reworked networking:
    * 'debug' network removed.
    * auto-generation of IP and MAC addresses.
* Disabled Nix tooling in release builds.
* Hotplugging of GPS devices.
* Hardened systemd config in gui-vm.
* Chromecast support on a normal browser.
* Added keybindings to move the active window to the next or previous desktop.
* Logging improvements.
* Window Manager widget added.
* VM-level Audio Control added.
* XDG-handlers using GIVC instead of SSH.
* File system changes for debug builds: ext4 used for root, btrfs for persistence partition.
* MitmWebUI app replaces mitmweb-ui script in chrome-vm.

Nvidia Jetson Orin AGX/NX:

* JetPack 6.2 including NVIDIA Jetson Linux 36.4.3 with Linux kernel 5.15.
* Docker with Nvidia container and CUDA 12.x support.
* Podman support, disabled by default.

## Bug Fixes

Fixed bugs that were present in the [ghaf-24.12](../release_notes/ghaf-24.12.md) release:

* A laptop cannot be unlocked after suspension sometimes.
* Audio output via 3.5mm jack doesn't work.
* Missing application menu icons on the first boot after the software installation.
* Location sharing does not work.
* File manager not displaying downloaded file.
* The application menu cannot be accessed using the Windows key

## Known Issues and Limitations



| Issue           | Status      | Comments                             |
|-----------------|-------------|--------------------------------------|
| **Lenovo X1**  |  |  |
| GALA app is not supported in this version of Ghaf | In Progress | |
| Sending bug report from Control Panel causes Control Panel to crash | In Progress | Under investigation |
| Intermittent issue of losing audio after boot or after log-out/log-in | In Progress | Workaround: rebooting the system typically resolves the issue. |
| Control Panel functionality is limited: only Display Settings, Local and Timezone settings are functional | In Progress | Additional functionality will be implemented in future releases. |
| The keyboard defaults to the English layout on boot | In Progress | Workaround: use Alt+Shift to switch between English-Arabic-Finnish layout. |
| Yubikey for unlocking does not work | In Progress | A fix is currently in progress. |
| A laptop may wake from suspend without user interaction | In Progress | The issue is under investigation. |
| **NVIDIA Jetson AGX Orin / Orin NX**  |  |  |
| Firefox has been disabled | In Progress | Firefox will be re-enabled once upstream fixes are available. |
| The keyboard always boots up with the English layout | In Progress | Workaround: use Alt+Shift to switch between English-Arabic-Finnish layout. |
| The Suspend power option is not functioning as expected | In Progress | Behavior is locking the device. |

## Environment Requirements

There are no specific requirements for the environment with this release.

## Installation Instructions

Released images are available at [ghafreleasesstorage.z16.web.core.windows.net/ghaf-25-03](https://ghafreleasesstorage.z16.web.core.windows.net/ghaf-25-03).

Download the required image and use the following instructions: [Build and Run](../ref_impl/build_and_run.md).
