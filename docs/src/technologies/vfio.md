<!--
    Copyright 2022-2023 TII (SSRC) and the Ghaf contributors
    SPDX-License-Identifier: CC-BY-SA-4.0
-->

# Binding Devices to VFIO Driver to Allow Passthrough

An example of binding a PCI device to the VFIO driver manually:

```
export DEVICE="0001:01:00.0"
export VENDOR_ID=$(cat /sys/bus/pci/devices/$DEVICE/vendor)
export DEVICE_ID=$(cat /sys/bus/pci/devices/$DEVICE/device)

echo "$DEVICE" > /sys/bus/pci/devices/$DEVICE/driver/unbind

echo "$VENDOR_ID $DEVICE_ID" > /sys/bus/pci/drivers/vfio-pci/new_id
```

Similar approach also works for platform devices. The device path for platform
 devices is `/sys/bus/platform/devices/$DEVICE/`.

```
export DEVICE="31d0000.serial"
echo vfio-platform > /sys/bus/platform/devices/$DEVICE/driver_override
echo "$DEVICE" > /sys/bus/platform/drivers/vfio-platform/bind
```


## Using driverctl Package

[driverctl](https://gitlab.com/driverctl/driverctl) is an open-source device
driver control utility for Linux systems. With `driverctl` it is easier to set
up VFIO or change the driver for a device:

```
export DEVICE="0001:01:00.0"
driverctl --nosave set-override ${DEVICE} vfio-pci
```

or for platform bus device passthrough
```
export DEVICE="31d0000.serial"
driverctl --nosave --bus platform set-override ${DEVICE} vfio-platform
```

It is important to note that by default `driverctl` stores the set driver
overrides and reactivates the override after a device reboot. With VFIO this
can cause issues since some hardware devices may be required while the device
starts up. This behavior can be effected by using the `--nosave` option as in
the example above so that the override is reset back to default at reboot.

The `driverctl` tool also features a way to list devices based on their bus type
 with the `list-devices` command.

 ```
# Default usage of the tool is for pci bus
driverctl list-devices

# Using command line option --bus platform sets the usage for platform bus
driverctl --bus platform list-devices
```

driverctl can also reset the default driver by using the `unset-override`
command.

```
export DEVICE="0001:01:00.0"
driverctl unset-override ${DEVICE}
```
