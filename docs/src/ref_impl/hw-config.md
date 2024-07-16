<!--
    Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
    SPDX-License-Identifier: CC-BY-SA-4.0
-->

# Hardware Configuration

All configuration files for reference target devices are in [modules/hardware](https://github.com/tiiuae/ghaf/tree/main/modules/hardware).

The ghaf-24.06 release supports the following target hardware:

* NVIDIA Jetson AGX Orin
* NVIDIA Jetson Orin NX
* Generic x86 (PC)
* Polarfire Icicle Kit
* Lenovo ThinkPad X1 Carbon Gen 11
* Lenovo ThinkPad X1 Carbon Gen 10
* NXP i.MX 8M Plus

To add a new hardware configuration file, do the following:

1. Create a separate folder for the device in [modules/hardware](https://github.com/tiiuae/ghaf/tree/main/modules/hardware).
2. Create the new configuration file with hardware-dependent parameters like host information, input and output device parameters, and others.
   
   You can use an already existing file as a reference, for example [modules/hardware/lenovo-x1/definitions/x1-gen11.nix](https://github.com/tiiuae/ghaf/blob/main/modules/hardware/lenovo-x1/definitions/x1-gen11.nix). 
