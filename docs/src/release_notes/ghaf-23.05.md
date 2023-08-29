<!--
    Copyright 2022-2023 TII (SSRC) and the Ghaf contributors
    SPDX-License-Identifier: CC-BY-SA-4.0
-->

# Release ghaf-23.05


## Release Branch

<https://github.com/tiiuae/ghaf/tree/ghaf-23.05>

## Supported Hardware

The following target hardware is supported by this release:

* NXP i.MX 8QM-MEK
* NVIDIA Jetson AGX Orin
* Generic x86 (PC)


## What is New in ghaf-23.05

This is the first release of Ghaf including support for:

* the Wayland display server protocol (on the host)
* the graphical interface with Weston Window Manager (on the host)
* the Chromium browser (on the host)
* Element, a Matrix-based chat client (on the host)
* the Google Android look-alike (GALA) application

> Ghaf Framework is under active development, some of the features may not be stable.


## Known Issues and Limitations

* Build time is used as the current time on NVIDIA Jetson AGX Orin.
  * Prevents logging into GALA and Element applications.
* Personal security keys cannot be created:
  * Prevents running Android in the Cloud.
  * Workaround: use another device to create security keys.
* NVIDIA Jetson AGX Orin: сannot open windows-launcher using a shortcut or a command line.
* No audio in a USB headset.
* Cannot log in to the Element chat with a Google account.
  * Workaround: create a separate user account for Element.