<!--
    Copyright 2022-2023 TII (SSRC) and the Ghaf contributors
    SPDX-License-Identifier: CC-BY-SA-4.0
-->

# Release ghaf-23.09


## Release Branch

<https://github.com/tiiuae/ghaf/tree/ghaf-23.09>


## Supported Hardware

The following target hardware is supported by this release:

* NVIDIA Jetson AGX Orin
* NVIDIA Jetson Orin NX
* Generic x86 (PC)
* Polarfire Icicle Kit
* Lenovo ThinkPad X1 Carbon Gen 11


## What is New in ghaf-23.09

* New supported target hardware:
  * NVIDIA Jetson Orin NX
  * Polarfire Icicle Kit
  * Lenovo ThinkPad X1 Carbon Gen 11
* Modularization of the Ghaf framework: [Ghaf as Library: Templates](../ref_impl/ghaf-based-project.md)
* NVIDIA Jetson Orin NX Ethernet passthrough.
* Lenovo X1 Carbon Gen 11:
  * Graphics passthrough to GUIVM.
  * Launching Application VMs through GUIVM (Chromium, Gala, and Zathura).
  * Paravirtualized audio.
  * Webcam passthrough.
  * Touchpad passthrough.
* Cross-compilation of the ARM targets (NVIDIA) on the x86 server (with demo apps excluded).


## Bug Fixes

Fixed bugs that were in the ghaf-23.06 release:

* NVIDIA Jetson AGX Orin:
  * Cannot open Windows launcher via shortcut or command line.
* No Windows launcher in x86 build.


## Known Issues and Limitations

| Issue           | Status      | Comments                             |
|-----------------|-------------|--------------------------------------|
| Chromium Application VM does not boot up on X1 | In Progress | Intermittent timing issue, under investigation. |
| The GALA app does not work | In Progress | Will be fixed in the next release. |
| Shutdown or reboot of Lenovo X1 takes a lot of time (7 minutes) | In Progress | Advice: be patient or, if in hurry, press power key for 15 sec. |
| Copy and paste text from or to Chromium Application VM does not work | In Progress |  |
| Element cannot be opened on NVIDIA AGX Orin HW on the host | Will not Fix | Applications on the host will not be supported in the longer term. |
| Cannot move the GALA/Element window by dragging with the mouse | In Progress | Workaround: press Windows key when moving the mouse. |
| Personal security keys cannot be created | In Progress | Workaround: use another device to create security keys. |
| No audio in a USB headset when running the application on the host | Will not Fix | Audio on a host is not supported. |
| Cannot log in to the Element chat with Google account  | In Progress | Workaround for x86: create a user specifically for Element. |
| Windows launcher application does not work  | In Progress | Workaround: launch Windows VM from the command line. |


## Environment Requirements

There are no specific requirements for the environment with this release.


## Installation Instructions

Released images are available at Jfrog Artifactory. To download the release image:

* In the [Jfrog Artifactory](https://artifactory.ssrcdevops.tii.ae/ui/login/) login screen, use the *Sign in with SAML SSO* option and then *Sign in with Github.com account*. Note that domain restrictions are in place.
* Navigate to the ghaf-23.09 directory: <https://artifactory.ssrcdevops.tii.ae/artifactory/tc/releases/ghaf-23.06/>
* Download the image from the `../targetHW/image` directory.