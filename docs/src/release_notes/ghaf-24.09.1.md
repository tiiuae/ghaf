<!--
    Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
    SPDX-License-Identifier: CC-BY-SA-4.0
-->

# Release ghaf-24.09.1

This patch release is targeted at [Secure Laptop](../scenarios/showcases.md#secure-laptop) (Lenovo X1 Carbon) test participants and brings in new features and bug fixes.

Lenovo X1 Carbon has been fully tested for this release, other platforms have been sanity-tested only.


## Release Tag

<https://github.com/tiiuae/ghaf/releases/tag/ghaf-24.09.1>


## Supported Hardware

The following target hardware is supported by this release:

* NVIDIA Jetson AGX Orin
* NVIDIA Jetson Orin NX
* Generic x86 (PC)
* Polarfire Icicle Kit
* Lenovo ThinkPad X1 Carbon Gen 11
* Lenovo ThinkPad X1 Carbon Gen 10
* NXP i.MX 8M Plus


## What is New in ghaf-24.09.1

Lenovo X1 Carbon Gen 10/11:

  * Audio Control and [Xarchiver](https://github.com/ib/xarchiver) file compression applications.
  * Network Manager applet.
  * The first version of the Control Panel (mainly non-functional).
  * Log Out and Lock buttons were moved to the power menu.
  * Shutdown and Reboot buttons were removed from the applications menu and are now available in the Power menu.
  * Multiple monitors support.


## Bug Fixes

Fixed bugs that were in the ghaf-24.09 release:

* It is impossible to change the Wi-Fi network from the Network Settings application.
* The taskbar on extended display is visible only when booting up with HDMI connected.
* The Mute status is not visible in the taskbar.


## Known Issues and Limitations

| Issue           | Status      | Comments                             |
|-----------------|-------------|--------------------------------------|
| The external USB camera is not working on Chromium VM  | In Progress | A fix is in progress. |
| Cannot log in to the Element chat with a Google account  | In Progress | Workaround: create a user specifically for Element. |
| Time synchronization between host and VMs does not work in all scenarios  | In Progress | Under investigation. |
| Suspend does not work from the taskbar power menu  | In Progress | Under investigation. |
| VPN credentials are not saved  | On Hold | Not clear if this can be fixed. |
| The keyboard boots up with the English layout   | In Progress | Workaround: use Alt+Shift to switch between English-Arabic-Finnish layout. |
| Bluetooth notification windows stay on a screen   | In Progress | Workaround: use the Esc key to remove pop-up windows. |


## Environment Requirements

There are no specific requirements for the environment with this release.


## Installation Instructions

Released images are available at [ghafreleasesstorage.z16.web.core.windows.net/ghaf-24-09-1](https://ghafreleasesstorage.z16.web.core.windows.net/ghaf-24-09-1).

Download the required image and use the following instructions: [Build and Run](../ref_impl/build_and_run.md).

