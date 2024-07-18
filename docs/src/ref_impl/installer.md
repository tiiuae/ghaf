<!--
    Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
    SPDX-License-Identifier: CC-BY-SA-4.0
-->

# Installer


## Configuring and Building Installer for Ghaf

You can obtain the installation image for your Ghaf configuration. 

In addition to the live USB image that Ghaf provides it is also possible to install Ghaf. This can either be achieved by downloading the desired image or by building it as described below.

Currently, only x86_64-linux systems are supported by the standalone installer.

To build, for example, the debug image for the Lenovo x1, use the following command:

```sh
nix build .#lenovo-x1-carbon-gen11-debug-installer
```


## Flashing Installer 

Once built you must transfer it to the desired installation media. It requires at least a 4GB SSD, at the time of writing.

```nix
sudo dd if=./result/iso/ghaf-<version>-x86_64-linux.iso of=/dev/<SSD_NAME> bs=32M status=progress; sync
```


## Installing Image

> [!CAUTION]
> This operation is destructive and will overwrite your system.

Insert the SSD into the laptop, boot, and select the option to install.

Then use the following command:

```nix
sudo ghaf-install.sh
```

Check the available options shown in the prompt for the install target. Mind that the `/dev/sdX` is likely the install medium.

Once entered, include `/dev` and press [Enter] on the keyboard to complete the process.

```nix
sudo reboot
```
Remove the installer drive.
