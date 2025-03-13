<!--
    Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
    SPDX-License-Identifier: CC-BY-SA-4.0
-->

# Release ghaf-24.09.2

This patch release is targeted at [Secure Laptop](../scenarios/showcases.md#secure-laptop) (Lenovo X1 Carbon) test participants and brings in new features and bug fixes.

Lenovo X1 Carbon has been fully tested for this release, other platforms have been sanity-tested only.


## Release Tag

<https://github.com/tiiuae/ghaf/releases/tag/ghaf-24.09.2>


## Supported Hardware

The following target hardware is supported by this release:

* NVIDIA Jetson AGX Orin
* NVIDIA Jetson Orin NX
* Generic x86 (PC)
* Polarfire Icicle Kit
* Lenovo ThinkPad X1 Carbon Gen 11
* Lenovo ThinkPad X1 Carbon Gen 10
* NXP i.MX 8M Plus


## What is New in ghaf-24.09.2

Lenovo X1 Carbon Gen 10/11:

  * Wayland security context protocol enabled.
  * The timeout of the Autolock feature at which re-entry of login and password is required has been fixed. Also, the screen dim intensity was adjusted.
  * Taskbar control for two virtual desktops.
  * Taskbar audio and brightness control responsiveness improved.
  * The closing widgets feature is available when clicking outside their area.
  * Zoom web application added into comms-vm.
  * Display resolution and Scale settings added to the Control Panel.


## Bug Fixes

* The USB camera is not working on Chromium VM.
* Double login issue with the Autolock feature on.
* The Control Panel is causing a high CPU load in GUI VM.
* Volume and brightness pop-ups do not close automatically.


## Known Issues and Limitations

| Issue           | Status      | Comments                             |
|-----------------|-------------|--------------------------------------|
| The Control Panel is non-functional apart from Display settings   | In Progress |  |
| Cannot log in to the Element chat with a Google account  | In Progress | Workaround: create a user specifically for Element. |
| Time synchronization between host and VMs does not work in all scenarios  | In Progress | Under investigation. |
| Suspend does not work from the taskbar power menu  | In Progress | Under investigation. |
| VPN credentials are not saved  | On Hold | Not clear if this can be fixed. |
| The keyboard boots up with the English layout   | In Progress | Workaround: use Alt+Shift to switch between English-Arabic-Finnish layout. |
| Bluetooth notification windows stay on a screen   | In Progress | Workaround: use the Esc key to remove pop-up windows. |


## Environment Requirements

There are no specific requirements for the environment with this release.


## Installation Instructions

Released images are available at [ghafreleasesstorage.z16.web.core.windows.net/ghaf-24-09-2](https://ghafreleasesstorage.z16.web.core.windows.net/ghaf-24-09-2).

Download the required image and use the following instructions: [Build and Run](../ref_impl/build_and_run.md).

