<!--
    Copyright 2022-2025 TII (SSRC) and the Ghaf contributors
    SPDX-License-Identifier: CC-BY-SA-4.0
-->

# Release ghaf-25.04

This is a monthly Ghaf release which has been fully tested on Nvidia Orin NX, Nvidia Orin AGX and Lenovo X1 Carbon Gen11 platforms. This release contains a major update of upgrading Linux kernel for Nvidia platforms to 6.6.75

This release complies with SLSA v1.0 level 3 requirements.


## Release Tag

https://github.com/tiiuae/ghaf/releases/tag/ghaf-25.04

## Supported Hardware

The following target hardware is supported by this release:

* NVIDIA Jetson AGX Orin
* NVIDIA Jetson Orin NX
* Lenovo ThinkPad X1 Carbon Gen 10, 11, 12
* Dell Latitude 7230, 7330
* Alienware M18 
* NXP i.MX 8M Plus

## What's Changed
* Add netvm kernel params and rtl8126 by @mbssrc in https://github.com/tiiuae/ghaf/pull/1108
* Demo desktop by @brianmcgillion in https://github.com/tiiuae/ghaf/pull/1107
* docs:add release note 25.03 by @clayhill66 in https://github.com/tiiuae/ghaf/pull/1111
* feat(graphics): add idle management configuration option by @kajusnau in https://github.com/tiiuae/ghaf/pull/1110
* nvidia: generalize the setup by @brianmcgillion in https://github.com/tiiuae/ghaf/pull/1109
* bump: standard bump by @brianmcgillion in https://github.com/tiiuae/ghaf/pull/1033
* docs: fix formatting and typo in release note by @clayhill66 in https://github.com/tiiuae/ghaf/pull/1116
* Orin NX/AGX: Switch from nvidia bsp 5.15 kernel to upstream 6.6 by @TanelDettenborn in https://github.com/tiiuae/ghaf/pull/1115
* vulkan: Add vulkan support for nvidia by @brianmcgillion in https://github.com/tiiuae/ghaf/pull/1117
* build(deps): bump actions/dependency-review-action from 4.5.0 to 4.6.0 by @dependabot in https://github.com/tiiuae/ghaf/pull/1118
* build(deps): bump cachix/install-nix-action from 31.0.0 to 31.1.0 by @dependabot in https://github.com/tiiuae/ghaf/pull/1119
* VPN: Add wireguard-gui service by @enesoztrk in https://github.com/tiiuae/ghaf/pull/1099
* UI Idle management by @mbssrc in https://github.com/tiiuae/ghaf/pull/1120
* Update SCS section in Ghaf github.io pages by @ktusawrk in https://github.com/tiiuae/ghaf/pull/1123
* Bug fix SSRCSP-5890 by @gngram in https://github.com/tiiuae/ghaf/pull/1121
* build(deps): bump step-security/harden-runner from 2.11.0 to 2.11.1 by @dependabot in https://github.com/tiiuae/ghaf/pull/1124
* chore: update pull request template by @kajusnau in https://github.com/tiiuae/ghaf/pull/1127
* Fix hw name by @brianmcgillion in https://github.com/tiiuae/ghaf/pull/1130
* build(deps): bump tj-actions/changed-files from 46.0.3 to 46.0.4 by @dependabot in https://github.com/tiiuae/ghaf/pull/1131
* VPN: wireguard-gui integration to ghaf control panel by @enesoztrk in https://github.com/tiiuae/ghaf/pull/1129
* debug: add some additional tools by @brianmcgillion in https://github.com/tiiuae/ghaf/pull/1132
* feat: power manager module, refactor ghaf-powercontrol by @kajusnau in https://github.com/tiiuae/ghaf/pull/1125
* build(deps): bump github/codeql-action from 3.28.13 to 3.28.14 by @dependabot in https://github.com/tiiuae/ghaf/pull/1134
* fix: fix the xhci pt in gui-vm by @brianmcgillion in https://github.com/tiiuae/ghaf/pull/1133
* bump: need the new firefox by @brianmcgillion in https://github.com/tiiuae/ghaf/pull/1122
* fix: devshell by @brianmcgillion in https://github.com/tiiuae/ghaf/pull/1136
* vhotplug: Enable type-c display for x86_64 variants by @vunnyso in https://github.com/tiiuae/ghaf/pull/1135
* build(deps): bump github/codeql-action from 3.28.14 to 3.28.15 by @dependabot in https://github.com/tiiuae/ghaf/pull/1137
* Refactor: Imports structure by @mbssrc in https://github.com/tiiuae/ghaf/pull/1085
* Refactor: Add PCI devices to common by @mbssrc in https://github.com/tiiuae/ghaf/pull/1138
* Fix typo by @mbssrc in https://github.com/tiiuae/ghaf/pull/1140
* Fix ci devshell by @brianmcgillion in https://github.com/tiiuae/ghaf/pull/1142
* Github actions: Evaluate devShells by @henrirosten in https://github.com/tiiuae/ghaf/pull/1139
* keys: Add Milla to known devs by @brianmcgillion in https://github.com/tiiuae/ghaf/pull/1144
* docs: Update Chapter 7. CI/CD in github.io pages by @ktusawrk in https://github.com/tiiuae/ghaf/pull/1143
* fix: graphics dropped in refactor by @brianmcgillion in https://github.com/tiiuae/ghaf/pull/1145
* build(deps): bump tj-actions/changed-files from 46.0.4 to 46.0.5 by @dependabot in https://github.com/tiiuae/ghaf/pull/1146
* firefox: Make in to a reference program by @brianmcgillion in https://github.com/tiiuae/ghaf/pull/1147
* desktop: add COSMIC Epoch DE by @kajusnau in https://github.com/tiiuae/ghaf/pull/1104
* bump nixos-hardware by @gngram in https://github.com/tiiuae/ghaf/pull/1148
* bump: fix wireguard-gui flake file for check command by @enesoztrk in https://github.com/tiiuae/ghaf/pull/1151
* bump: nixos-hardware by @gngram in https://github.com/tiiuae/ghaf/pull/1153
* Update vhotplug to fix issues with multiple devices with the same VID/PID by @nesteroff in https://github.com/tiiuae/ghaf/pull/1149
* keys: Add new nixos key for rodrigo by @brianmcgillion in https://github.com/tiiuae/ghaf/pull/1156
* bump: standard bump by @brianmcgillion in https://github.com/tiiuae/ghaf/pull/1150
* intel-gpu: Cleanup the intel setup configuration by @vunnyso in https://github.com/tiiuae/ghaf/pull/1157
* build(deps): bump cachix/install-nix-action from 31.1.0 to 31.2.0 by @dependabot in https://github.com/tiiuae/ghaf/pull/1160
* bugfix: fix Falcon AI app not starting, rework package by @kajusnau in https://github.com/tiiuae/ghaf/pull/1154
* Input devices: remove hardcoded evdevs by @mbssrc in https://github.com/tiiuae/ghaf/pull/1159
* GhA: Authorize workflow by @henrirosten in https://github.com/tiiuae/ghaf/pull/1161
* build(deps): bump step-security/harden-runner from 2.11.1 to 2.12.0 by @dependabot in https://github.com/tiiuae/ghaf/pull/1162
* GhA: authorize.yml: url-encode actor by @henrirosten in https://github.com/tiiuae/ghaf/pull/1163
* Adapt to microvm changes by @slakkala in https://github.com/tiiuae/ghaf/pull/1165
* GhA:  warn also on authorize.yml change by @henrirosten in https://github.com/tiiuae/ghaf/pull/1166
* Support for AGX 64 GB is added with different target options. by @emrahbillur in https://github.com/tiiuae/ghaf/pull/1164
* build(deps): bump github/codeql-action from 3.28.15 to 3.28.16 by @dependabot in https://github.com/tiiuae/ghaf/pull/1167
* testing: replace speedtest-cli with ookla by @brianmcgillion in https://github.com/tiiuae/ghaf/pull/1168
* Fix: ids-vm networking by @mbssrc in https://github.com/tiiuae/ghaf/pull/1170
* version number fix by @brianmcgillion in https://github.com/tiiuae/ghaf/pull/1172

## New Contributors
* @ktusawrk made their first contribution in https://github.com/tiiuae/ghaf/pull/1123

**Full Changelog**: https://github.com/tiiuae/ghaf/compare/ghaf-25.03...ghaf-25.04

## Bug Fixes

Fixed bugs that were present in the [ghaf-25.03](../release_notes/ghaf-25.03.md) release:

* Nvidia Orin AGX 64G is supported as a separate build target
* Falcon AI app starting issue fixed
* vhotplug updated to fix issues with multiple devices with the same VID/PID

## Known Issues and Limitations



| Issue           | Status      | Comments                             |
|-----------------|-------------|--------------------------------------|
| The keyboard defaults to the English layout on boot | In Progress | Workaround: use Alt+Shift to switch between English-Arabic-Finnish layout. |
|Element app is not supported in this version of Ghaf | On hold | |
| **Lenovo X1**  |  |  |
| Downloading large file (10G) crashes the browser | In progress | Issue is under investigation |
| GALA app is not supported in this version of Ghaf | On hold | |
| Sending bug report from Control Panel causes Control Panel to crash | In Progress | Fix is in progress |
| Control Panel functionality is limited: only Display Settings, Local and Timezone settings are functional | In Progress | Additional functionality will be implemented in future releases. |
| Yubikey for unlocking does not work | In Progress | A fix is currently in progress. |
| A laptop may wake from suspend without user interaction | In Progress | The issue is under investigation. |
| **NVIDIA Jetson AGX Orin / Orin NX**  |  |  |
| Firefox has been disabled | In Progress | Firefox will be re-enabled once upstream fixes are available. |
| The Suspend power option is not functioning as expected | In Progress | Behavior is locking the device. |

## Installation Instructions

Released images are available at [archive.vedenemo.dev/ghaf-25.04](https://archive.vedenemo-dev/ghaf-25.04).

Download the required image and use the following instructions: [Build and Run](../ref_impl/build_and_run.md).
