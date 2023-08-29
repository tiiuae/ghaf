<!--
    Copyright 2022-2023 TII (SSRC) and the Ghaf contributors
    SPDX-License-Identifier: CC-BY-SA-4.0
-->

# Release ghaf-23.06


## Release Branch

<https://github.com/tiiuae/ghaf/tree/ghaf-23.06>

## Supported Hardware

The following target hardware is supported by this release:

* NXP i.MX 8QM-MEK
* NVIDIA Jetson AGX Orin
* Generic x86 (PC)


## What is New in ghaf-23.06

* Ghaf Modularization (partially done):
  * general description and context on how to use: [Ghaf-Based Project](../ref_impl/ghaf-based-project.md)
  * the development status: <https://github.com/tiiuae/ghaf/tree/ghaf-23.06/modules>
* SLSA v1.0 level provenance file included.
* Ghaf version information (query).
* NixOS is updated to 23.05: [NixOS 23.05 released!](https://discourse.nixos.org/t/nixos-23-05-released/28649)


## Bug Fixes

Build time is used as the current time on NVIDIA Jetson AGX Orin.


## Known Issues and Limitations

* Known since ghaf-23.05:
  * Personal security keys cannot be created.
  * NVIDIA Jetson AGX Orin: сannot open windows-launcher using a shortcut or a command line.
  * No audio in a USB headset.
  * Cannot log in to the Element chat with a Google account
    * Workaround for x86: create a separate user account for Element.
* Element cannot be opened on NVIDIA Jetson AGX Orin.
* Cannot move the GALA/Element window by dragging with the mouse.
* No windows-launcher in the x86 build.