<!--
    Copyright 2022-2025 TII (SSRC) and the Ghaf contributors
    SPDX-License-Identifier: CC-BY-SA-4.0
-->

# Release ghaf-24.12.3

This is a bi-weekly release with a major update to JetPack 6.2 for NVIDIA platforms.


## Release Tag

<https://github.com/tiiuae/ghaf/releases/tag/ghaf-24.12.3>


## Supported Hardware

The following target hardware is supported by this release:

* NVIDIA Jetson AGX Orin
* NVIDIA Jetson Orin NX
* Generic x86 (PC)—build support only
* Lenovo ThinkPad X1 Carbon Gen 10, 11, 12
* NXP i.MX 8M Plus—build support only


## What is New in ghaf-24.12.3


Lenovo X1 Carbon:

  * Window Manager widget added.
  * VM-level Audio Control added.
  * XDG-handlers using GIVC instead of SSH.


NVIDIA Jetson Orin AGX/NX:

  * JetPack 6.2 including NVIDIA Jetson Linux 36.4.3 with Linux kernel 5.15.


## Bug Fixes

Fixed bugs that were present in the [ghaf-24.12.2](../release_notes/ghaf-24.12.2.md) release:

* Audio output via 3.5mm jack.
* Missing application menu icons on the first boot after the software installation.


## Known Issues and Limitations

| Issue           | Status      | Comments                             |
|-----------------|-------------|--------------------------------------|
| **Lenovo X1**  |  |  |
| Location sharing does not work  | In Progress | The issue is under investigation. |
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

Released images are available at [ghafreleasesstorage.z16.web.core.windows.net/ghaf-24-12.3](https://ghafreleasesstorage.z16.web.core.windows.net/ghaf-24-12-3).

Download the required image and use the following instructions: [Build and Run](../ref_impl/build_and_run.md).