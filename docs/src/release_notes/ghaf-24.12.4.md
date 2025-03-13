<!--
    Copyright 2022-2025 TII (SSRC) and the Ghaf contributors
    SPDX-License-Identifier: CC-BY-SA-4.0
-->


# Release ghaf-24.12.4

This is a bi-weekly release for Ghaf adding support for Nvidia containers and CUDA 12.x for Nvidia platforms based on JetPack 6


## Release Tag

<https://github.com/tiiuae/ghaf/releases/tag/ghaf-24.12.4>


## Supported Hardware

The following target hardware is supported by this release:

* NVIDIA Jetson AGX Orin
* NVIDIA Jetson Orin NX
* Lenovo ThinkPad X1 Carbon Gen 10, 11, 12
* Dell Latitude 7230, 7330
* Alienware M18 
* Generic x86 (PC)
* NXP i.MX 8M Plus - build support only


## What is New in ghaf-24.12.4


 *  General refactoring and modularization 
 *  Support for Alienware M18 laptop added

Lenovo X1 Carbon / x86 platforms:

 *   File system changes for debug builds: ext4 used for root, btrfs for persistence partition
 *   MitmWebUI app replaces mitmweb-ui script in chrome-vm

Nvidia Jetson Orin AGX/NX:

 *   Docker with Nvidia container and CUDA 12.x support
 *   Podman support, disabled by default
 

## Bug Fixes

Fixed bugs that were present in the [ghaf-24.12.3](../release_notes/ghaf-24.12.3.md) release:

*   Location sharing does not work
*   File manager not displaying downloaded file


## Known Issues and Limitations

Note: Provenance file signature verification failed with this release build due to issues in the build system

| Issue           | Status      | Comments                             |
|-----------------|-------------|--------------------------------------|
| **Lenovo X1**  |  |  |
| Sending bug report from Control Panel causes Control Panel to crash | In Progress | Under investigation |
| Intermittent audio issue after boot  | In Progress | Workaround: rebooting the system typically resolves the issue. |
| Control Panel functionality is limited: only Display Settings, Local and Timezone settings are functional | In Progress | Additional functionality will be implemented in future releases. |
| VPN credentials are not saved  | On Hold |  |
| The keyboard defaults to the English layout on boot | In Progress | Workaround: use Alt+Shift to switch between English-Arabic-Finnish layout. |
| Yubikey for unlocking does not work | In Progress | A fix is currently in progress. |
| A laptop may wake from suspend without user interaction | In Progress | The issue is under investigation. |
| **NVIDIA Jetson AGX Orin / Orin NX**  |  |  |
| Firefox has been disabled | In Progress | Firefox will be re-enabled once upstream fixes are available. |
| The application menu cannot be accessed using the Windows key | In Progress | Workaround: access the application menu through the taskbar in the top-left corner. |
| The keyboard always boots up with the English layout | In Progress | Workaround: use Alt+Shift to switch between English-Arabic-Finnish layout. |
| The Suspend power option is not functioning as expected | In Progress | Behavior is locking the device. |


## Environment Requirements

There are no specific requirements for the environment with this release.


## Installation Instructions

Released images are available at [ghafreleasesstorage.z16.web.core.windows.net/ghaf-24-12.4](https://ghafreleasesstorage.z16.web.core.windows.net/ghaf-24-12-4).

Download the required image and use the following instructions: [Build and Run](../ref_impl/build_and_run.md).