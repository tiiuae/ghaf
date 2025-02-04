<!--
    Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
    SPDX-License-Identifier: CC-BY-SA-4.0
-->

# Release ghaf-24.12.1

This bi-weekly release brings a major update on Ghaf dependencies, most notably the compiler GCC 14 version.


## Release Tag

<https://github.com/tiiuae/ghaf/releases/tag/ghaf-24.12.1>


## Supported Hardware

The following target hardware is supported by this release:

* NVIDIA Jetson AGX Orin
* NVIDIA Jetson Orin NX
* Generic x86 (PC) (build support only)
* Lenovo ThinkPad X1 Carbon Gen 11
* Lenovo ThinkPad X1 Carbon Gen 10
* NXP i.MX 8M Plus (build support only)


## What is New in ghaf-24.12.1

  * Major update on upstream dependencies.
  * More robust user account management.
  * RISC-V Polarfire Icicle Kit builds are currently disabled but can be re-enabled if needed.

Lenovo X1 Carbon Gen 10/11:

  * Audio device selection and microphone slider are added to the quick settings widget.
  * Audio control was removed from the application menu.


## Bug Fixes

Fixed bugs that were present in the [ghaf-24.12](../release_notes/ghaf-24.12.md) release:

* A laptop cannot be unlocked after suspension sometimes.


## Known Issues and Limitations

| Issue           | Status      | Comments                             |
|-----------------|-------------|--------------------------------------|
| **Lenovo X1**  |  |  |
| No audio output via 3.5mm jack  | In Progress | Workaround: connect the device before booting up. |
| Intermittent audio issue after boot  | In Progress | Workaround: rebooting the system typically resolves the issue. |
| Missing application menu icons on the first boot after the software installation  | In Progress | Workaround: close and re-open the menu to restore icons. |
| Control Panel functionality is limited: only Display Settings, Local and Timezone settings are functional | In Progress | Additional functionality will be implemented in future releases. |
| VPN credentials are not saved  | On Hold |  |
| The keyboard defaults to the English layout on boot | In Progress | Workaround: use Alt+Shift to switch between English-Arabic-Finnish layout. |
| Yubikey for unlocking does not work | In Progress | A fix is currently in progress. |
| The fingerprint scan login does not function | Will Not Be Fixed | Fingerprint authentication will not be supported. Unlocking with a fingerprint is supported. |
| A laptop may wake from suspend without user interaction | In Progress | The issue is under investigation. |
| **NVIDIA Jetson AGX Orin / Orin NX**  |  |  |
| Firefox has been disabled | In Progress | Firefox will be re-enabled once upstream fixes are available. |
| Missing application menu icons on the first boot after the software installation | In Progress | Workaround: close and re-open the menu to restore icons. |
| The application menu cannot be accessed using the Windows key | In Progress | Workaround: access the application menu through the taskbar in the top-left corner. |
| The keyboard always boots up with the English layout | In Progress | Workaround: use Alt+Shift to switch between English-Arabic-Finnish layout. |
| The Suspend power option is not functioning as expected | In Progress | Behavior is locking the device. |


## Environment Requirements

There are no specific requirements for the environment with this release.


## Installation Instructions

Released images are available at [ghafreleasesstorage.z16.web.core.windows.net/ghaf-24-12.1](https://ghafreleasesstorage.z16.web.core.windows.net/ghaf-24-12-01).

Download the required image and use the following instructions: [Build and Run](../ref_impl/build_and_run).