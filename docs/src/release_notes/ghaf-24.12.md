<!--
    Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
    SPDX-License-Identifier: CC-BY-SA-4.0
-->

# Release ghaf-24.12

This is a quarterly release for all supported hardware platforms, and it complies with SLSA v1.0 Level 3 requirements.


## Release Tag

<https://github.com/tiiuae/ghaf/releases/tag/ghaf-24.12>


## Supported Hardware

The following target hardware is supported by this release:

* NVIDIA Jetson AGX Orin
* NVIDIA Jetson Orin NX
* Generic x86 (PC)
* Polarfire Icicle Kit
* Lenovo ThinkPad X1 Carbon Gen 11
* Lenovo ThinkPad X1 Carbon Gen 10
* NXP i.MX 8M Plus (build support only)


## What is New in ghaf-24.12

Lenovo X1 Carbon Gen 10/11:

  * Chromium replaced with Google Chrome.
  * Zoom web application added into comms-vm.
  * Xarchiver file compression application added.
  * Audio Control, USB, and Network Manager applets added.
  * Bluetooth applet added to the system tray.
  * The first version of the Control Panel currently supports the following:
    * display resolution and scale settings;
    * locale and timezone settings.
  * The System Idle behavior has been reworked: the screen dims after 4 minutes of inactivity, the session locks in 5 minutes, the screen goes off in 7.5 minutes, and the system suspends in 15 minutes.
  * User account management has been added. The user sets a username and password when a device is first booted.
  * The username is displayed on a lock screen.
  * Dynamic updates of Microsoft endpoint URLs.
  * A separate configurable repository for adding allowed URLs for business-vm.
  * Auto-reconnect hotplugged devices when the VM restarts.
  * Wayland security context protocol enabled.
  * Refactored application definitions to make it easier to add and remove applications.
  * Hardened greetd.service.
  * AppArmor enabled.
  * Multiple user experience improvements.

Lenovo X1 and NVIDIA Jetson Orin NX/AGX Orin:

  * Lock and Log Out buttons moved from the applications menu to the power menu.
  * Shutdown and Reboot buttons were removed from the applications menu and are now available in the Power menu.
  * The Powerbar module is added to the lock screen.
  * Run-time multi-monitor support.
  * Taskbar control for four virtual desktops.
  * Development, testing, and performance tooling improvements.


## Bug Fixes

Fixed bugs that were present in the [ghaf-24.09](../release_notes/ghaf-24.09.md) release:

* It is impossible to change the Wi-Fi network from the Network Settings application.
* Cannot connect to a hidden Wi-Fi network from GUI.
* The taskbar on the extended display is visible only when booting up with an HDMI connection.
* Suspend does not work from the taskbar power menu.
* The Mute status is not visible in the taskbar.
* Bluetooth notification windows stay on a screen.
* Time synchronization between host and VMs does not work in all scenarios.


## Known Issues and Limitations

| Issue           | Status      | Comments                             |
|-----------------|-------------|--------------------------------------|
| **Lenovo X1**  |  |  |
| Application menu icons are missing in the first boot after the software installation   | In Progress | Workaround: close and re-open the menu, icons will be available again. |
| The Control Panel is non-functional apart from the Display Settings, Local and Timezone settings   | In Progress | The functionality will be gradually improved in coming releases. |
| VPN credentials are not saved   | On Hold |  |
| The keyboard always boots up with the English layout   | In Progress | Workaround: use Alt+Shift to switch between English-Arabic-Finnish layout. |
| Yubikey for unlocking does not work   | In Progress | Fix in progress. |
| The fingerprint scan login does not work   | In Progress | Fix in progress. |
| A laptop cannot be unlocked after suspension sometimes   | In Progress | Fix in progress. Workaround: log out and log in again. |
| A laptop may wake up from a suspended state without user interaction   | In Progress | Under investigation. |
| **NVIDIA Jetson AGX Orin / Orin NX**  |  |  |
| Application menu icons are missing in the first boot after the software installation   | In Progress | Workaround: close and re-open the menu, icons will be available again. |
| The application menu access does not work with the Windows key   | In Progress | Workaround: the application menu can be accessed through the taskbar in the top left corner. |
| The keyboard always boots up with the English layout    | In Progress | Workaround: use Alt+Shift to switch between English-Arabic-Finnish layout. |
| The Suspend power option does not work    | In Progress | Behavior is locking the device. |


## Environment Requirements

There are no specific requirements for the environment with this release.


## Installation Instructions

Released images are available at [ghafreleasesstorage.z16.web.core.windows.net/ghaf-24-12](https://ghafreleasesstorage.z16.web.core.windows.net/ghaf-24-12).

Download the required image and use the following instructions: [Build and Run](../ref_impl/build_and_run.md).

