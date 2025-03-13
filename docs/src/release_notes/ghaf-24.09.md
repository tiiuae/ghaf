<!--
    Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
    SPDX-License-Identifier: CC-BY-SA-4.0
-->

# Release ghaf-24.09


## Release Tag

<https://github.com/tiiuae/ghaf/releases/tag/ghaf-24.09>


## Supported Hardware

The following target hardware is supported by this release:

* NVIDIA Jetson AGX Orin
* NVIDIA Jetson Orin NX
* Generic x86 (PC)
* Polarfire Icicle Kit
* Lenovo ThinkPad X1 Carbon Gen 11
* Lenovo ThinkPad X1 Carbon Gen 10
* NXP i.MX 8M Plus


## What is New in ghaf-24.09

* Lenovo X1 Carbon Gen 10/11:
  * Trusted Business VM with firewall protection containing the following applications: Microsoft 365 (with Outlook and Teams), Trusted Browser, Text Editor, Video Editor.
    * Integrated camera supported with Business VM applications.
  * The previous Element VM was modified to a more generic Comms VM, adding Slack..
  * GlobalProtect VPN client.
  * Centralized logging solution using [Grafana](https://grafana.com/grafana/).
  * The [ZFS](https://docs.oracle.com/cd/E19253-01/819-5461/zfsover-2/) file system and Logical Volume Manager (LVM).
  * Storage VM using the [NixOS Impermanence](https://github.com/nix-community/impermanence) framework.
  * USB hot plug supports input, audio, and media devices.
  * USB camera support on Chromium VM.
  * Initial version of file manager.
  * Hardware detection scanner to generate hardware definition files for different laptops.
  * GPU acceleration enabled.
  * [YubiKey](https://www.yubico.com/products/) authentication.
  * The [Falcon LLM](https://falconllm.tii.ae/falcon-models.html) AI model installed.
  * The greetd login manager with the system automatic screen lock enabled locks screen after 5 minutes of inactivity.
  * The UI [Waybar](https://github.com/Alexays/Waybar) was replaced by the [EWW (Elkowars Wacky Widgets)](https://github.com/elkowar/eww) taskbar.
  * Magnification, Sticky Notes, Screenshot, Calculator applications.
  * AppFlowy was disabled.
* NVIDIA Jetson Orin NX:
  * JetPack baseline software updates and fixes.
* Further refactoring and modularization of the Ghaf framework.
* Development, testing, and performance tooling improvements.


## Bug Fixes

Fixed bugs that were in the ghaf-24.06 release:

N/A


## Known Issues and Limitations

| Issue           | Status      | Comments                             |
|-----------------|-------------|--------------------------------------|
| **NVIDIA Jetson AGX Orin / Orin NX**  |  |  |
| Cannot log in to the Element chat with a Google account  | In Progress | Under investigation. |
| Screenshots cannot be taken successfully anymore  | In Progress | Under investigation. |
| Orin AGX/NX and NUC: no taskbar visible  | In Progress | Workaround: use the Windows key to open the menu. |
| Cannot connect to a hidden Wi-Fi network from GUI | In Progress | Workaround:  connect with SSH to a netvm and run the command: `nmcli dev wifi connect SSID password PASSWORD hidden yes`. |
| Cannot make voice calls using the Element application | In Progress | Under investigation. |
| The Element application cannot find a camera | In Progress | Under investigation. |
| **Lenovo X1**  |  |  |
| Cannot log in to the Element chat with a Google account  | In Progress | Workaround: create a user specifically for Element. |
| Time synchronization between host and VMs does not work in all scenarios  | In Progress | Under investigation. |
| It is impossible to change the Wi-Fi network from the Network Settings application  | In Progress | A fix is under verification. Workaround: remove the current network from the application. |
| The taskbar on extended display is visible only when booting up with HDMI connected  | In Progress | Under investigation. |
| Suspend does not work from the taskbar power menu  | In Progress | Under investigation. |
| The Mute status is not visible in the taskbar  | In Progress | A fix is in progress. |
| VPN credentials are not saved  | On Hold | Not clear if this can be fixed. |
| The keyboard boots up with the English layout   | In Progress | Workaround: use Alt+Shift to switch between English-Arabic-Finnish layout. |
| Bluetooth notification windows stay on a screen   | In Progress | Workaround: use the Esc key to remove pop-up windows. |


## Environment Requirements

There are no specific requirements for the environment with this release.


## Installation Instructions

Released images are available at [ghafreleasesstorage.z16.web.core.windows.net/ghaf-24-09](https://ghafreleasesstorage.z16.web.core.windows.net/ghaf-24-09).

Download the required image and use the following instructions: [Build and Run](../ref_impl/build_and_run.md).

