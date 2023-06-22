<!--
    Copyright 2022-2023 TII (SSRC) and the Ghaf contributors
    SPDX-License-Identifier: CC-BY-SA-4.0
-->

# x86 PCIe Device Passthrough with crosvm


## Enabling PCIe Devices for VFIO with driverctl

As with other passthroughs, first, we need to set the target device to use VFIO
 driver. This can be done manually or by using the [driverctl](https://gitlab.com/driverctl/driverctl) tool as below.
 
> Running driverctl requires root permissions.

```
export BUS="0000:01:00.0"
driverctl --nosave set-override ${BUS} vfio-pci
```

Let's consider the example of starting crosvm.

In some cases, crosvm may need privileged permissions to work properly. This
applies specially for passthrough hardware devices as vfio devices are
generally owned by the root user or the vfio group. For simplicity, it may be
easier to run crosvm as the root user but it is be possible to set up correct
permissions so that running as root is not needed.

Crosvm expects the device's system path as its `--vfio` argument.
 The device identifier is different when comparing how passthrough devices are
 refrenced in QEMU. Using the `guest-address` option is not strictly required
 by the source documentation but it gives a bit more control for handling the
 passthrough device on the guest side.

```
export BUS="0000:01:00.0"
export GUESTBUS="00:08.0"
./target/debug/crosvm run \
        --mem=8192 \
        --block ./ubuntu-22.10.img \
        -i /boot/initrd.img-5.19.0-31-generic /boot/vmlinuz-5.19.0-31-generic \
        -p "root=/dev/vda2 loglevel=8 earlycon earlyprintk debug" \
        --vfio /sys/bus/pci/devices/${BUS},guest-address=${GUESTBUS},iommu=viommu
```


## Reseting Driver to Original State Afterwards

The driverctl tool can reset the original device driver afterward:
```
export BUS="0000:01:00.0"
driverctl unset-override ${BUS}
```