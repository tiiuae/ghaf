<!--
    Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
    SPDX-License-Identifier: CC-BY-SA-4.0
-->

# Example Project

The compartmentalization could be applied to many specific x86_64 computers and laptops with some customization applied to the Ghaf.

The best way to do the Ghaf customization is by using Ghaf templates:

1. Create a template project as described in the [Ghaf as Library](../ref_impl/ghaf-based-project.md) section.
2. Adjust your system configuration in accordance with your HW specification. Determine all VIDs and PIDs of the devices that are passed to the VMs.
3. Add GUIVM configuration, NetworkVM configuration, and optionally some AppVMs.
4. Set up Weston panel shortcuts.

You can refer to the existing [project example for Lenovo T14 and Lenovo X1 laptops](https://github.com/unbel13ver/ghaf-lib).

Creating the structure that includes all necessary data for the device passthrough:

```
# File 'my-hardware/lenovo-t14.nix':
# Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# Generic x86_64 computer -target
{
  deviceName = "lenovo-t14";
  networkPciAddr = "0000:00:14.3";
  networkPciVid = "8086";
  networkPciPid = "02f0";
  gpuPciAddr = "0000:00:02.0";
  gpuPciVid = "8086";
  gpuPciPid = "9b41";
  usbInputVid = "046d";
  usbInputPid = "c52b";
}
```

The fields of that structure are self-explanatory. Use the `lspci -nnk` command to get this data from any Linux OS running on the device.


## Troubleshooting for Lenovo X1 Laptop

If after booting you see a black screen, try the following to detect the issue:

1. Add a Wi-Fi network name and password to the *lenovo-x1-carbon.nix* file instead of `#networks."ssid".psk = "psk"`.
2. Build and run the image. For more information, see [Running Ghaf Image for Lenovo X1](./build_and_run.md#running-ghaf-image-for-lenovo-x1).
3. Identify an IP address by a MAC address with the `arp` command. If a MAC address is unknown, you can boot into the NixOS image or any other OS to find it, or try the latest addresses that `arp` returns.
4. Connect using SSH (login/password ghaf/ghaf). Then connect from netvm to the host using `ssh 192.168.101.2` (login/password ghaf/ghaf).
5. Check running VMs with `microvm -l`.
6. Check a GUIVM log using `journalctl -u microvm@guivm`.
7. If GUIVM does not start, you can try to start it manually with `/var/lib/microvms/guivm/current/bin/microvm-run`.

In case when GUIVM did not start with the error message that the device /dev/mouse or /dev/touchpad was not found, it means that the model of the touchpad in the laptop is different since it was bought in another country and has a different SKU (stock keeping unit). To add support for a new touchpad, do the following:

1. On the ghaf host, check the devices in `/dev/input/by-path` that contain “-event-” in the name. Use the command like `udevadm info -q all -a /dev/input/by-path/pci-0000:00:15.0-platform-i2c_designware.0-event-mouse | grep name` for the name of each of these devices.

    > By name you can understand which devices belong to the touchpad. For example, on laptops in Finland they look like “SYNA8016:00 06CB:CEB3 Mouse” and “SYNA8016:00 06CB:CEB3 Touchpad”, and in the UAE they are “ELAN067C:00 04F3:31F9 Mouse” and “ELAN067C:00 04F3:31F9 Touchpad.”

2. If there are no such devices in `/dev/input/by-path`, then you can check the devices /dev/input/event* with a similar command.
3. When the necessary device names are found, add them to `services.udev.extraRules` in the *lenovo-x1-carbon.nix* file, rebuild the image and test the changes.