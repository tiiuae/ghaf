 <!--
    Copyright 2022-2023 TII (SSRC) and the Ghaf contributors
    SPDX-License-Identifier: CC-BY-SA-4.0
-->

# NVIDIA Jetson AGX Orin: PCIe passthrough

This document describes the PCIe passthrough implementations on the NVIDIA
 Jetson AGX Orin board. The goal of this document is to give an overview
 of passing through different PCIe devices and limitations of PCIe in AGX
 Orin board.

##  PCIe slots in Nvidia Jetson AGX Orin

There are two (or actually three) PCIe slots in Orin. One of the connectors
is full size 8x PCIe slot located under a black plastic cover above the micro
usb serial debug port on the side on Orin. The other slot is a smaller M2
slot, and it is located at the bottom of the Orin. By default, the slot is in
use of the included Wi-Fi and Bluetooth module. The third slot is actually an NVMe
slot which can be used to add an NVMe ssd to Orin.

There are a few things to consider when using one of the slots. First and
foremost always turn off and disconnect any power sources from the Orin
board and its peripheral when connecting or disconnecting devices on any of
the PCIe buses. When adding or removing devices on board there is always a
risk of setting off an electrical discharge in one of the components which may
damage the connected device or the board itself.

### Full size PCIe slot

The full size PCIe connector can be found under the black plastic cover on one
of the sides of the device. The cover is held in place with a fairly strong
magnet. There is a small connector ribbon and a few delicate wires going from
the board internals to a Wi-Fi antenna on the cover. Some care should be taken
when removing the cover for not ripping the whole cover off along with the
antenna cables.

The PCIe slot is exactly what you expect to find inside a full size desktop
computer. One key difference is that the Orin board has limited 12 volts power
output capabilities and Orin can only output maximum 40 watts of power to its
PCIe slot. Normal desktop PCIe slot can output 75watts at 12 Volts so some
more power hungry PCIe cards may not work with Orin. There may also be a risk
of damaging Orin if a card tries to pull too much power from the PCIe socket
it is advised to carefully check the power requirements of a device before
turning the device on. The more power hungry cards are usually some Graphics-
or other Accelerator cards. A good rule of thumb might be if the device has
a fan to actively cool it down then some care should be taken before starting
to use the card. Some trials have been done with GPU devices that use at
maximum 30-34 watts power. The devices seem to work well in Nvidia Orin, but it
is difficult to say how much power the card actually pulls from the slot at
any given time. No real performance or stress tests have been done but under
normal GUI and simple 3d application usage the cards (Nvidia Quadro P1000 and
Nvidia Quadro T600) seem to work fine.

### PCIe M2 slot

The PCIe M2 with key type A+E is at bottom of the board and is by default in
use of the internal Wi-Fi and Bluetooth card. There are different types of M2
slots all of which are not compatible with one another. The slot in Orin is
type A+E, and it supports PCIe 2x and USB transport buses.

### PCIe M2 NVMe 2247 for ssd

The third slot is M2 NVMe 2280 (22 mm width and 80 mm length) and can be used
for NVMe SSD. Passing through this interface has not been tested as the SSD is
in most cases used by the host.

## Enable PCIe devices for vfio

Similar to [UART Passthrough](nvidia_agx_pt_uart.md) the default device tree
needs some modifications. With the default configuration the PCI devices are
set to the same vfio group as the PCI bus itself. The problem with this is
that the PCI bus is a platform bus device which is a bit tricky to pass
through to guest. Luckily we can pass through only the individual PCI devices
and not the whole bus. To pass through individual PCI devices one by one needs
to set the devices in their individual vfio groups or in this case remove the
PCI bus from the same vfio group.

```cpp
/*
 * Modify the 'pcie_c1_rp' pci-e bus by removing its
 * iommu group definition.
 * This is to remove the pci bus from vfio group which
 * leaves the m2 pci device alone in the group.
 * This change is for the m2 pci-e "wifi" slot.
  */
&pcie_c1_rp {
    /delete-property/ iommus;
};

/*
 * Modify the 'pci_c5_rp' pci bus by removing its
 * iommu group definition.
 * This is to remove the pci bus from vfio group which
 * leaves the pci device alone in the group.
 * This change is for the full size pci-e slot.
 */
&pcie_c5_rp {
    /delete-property/ iommus;
};
```

### Bind a device for vfio

To set up the device for vfio the device driver needs to be unloaded and then
replaced with "vfio-pci" driver. The example below is for a device in the PCI
bus "0001". The only device "0001:01:00.0" in the first bus is the Nvidia Orin
the m2 Wi-Fi card. The full size PCI bus id is "0005". It is possible that
a single PCI card contains multiple devices. In that case all the devices
need to be passed through together as they are in the same vfio group. Usually
with graphics cards the graphics card also contains some sound output device
as a separate device.

```
export DEVICE="0001:01:00.0"
export VENDOR=$(cat /sys/bus/pci/devices/$DEVICE/vendor)
export DEVICE=$(cat /sys/bus/pci/devices/$DEVICE/device)

echo "$DEVICE" > /sys/bus/pci/devices/$DEVICE/driver/unbind

echo "$VENDOR $DEVICE" > /sys/bus/pci/drivers/vfio-pci/new_id
```

If everything went correctly this device is now bind to vfio. The vfio nodes
in are usually owned by root and in some cases may in some cases be group
accessible by vfio group. In any case to use the vfio devices the user
who starts Qemu needs permission to the vfio device node.
```
# List of vfio device <id> nodes
ls /dev/vfio/

# List of devices within each iommu group
ls /sys/kernel/iommu_groups/<id>/devices/
```

It is also possible to check which device belongs to which vfio iommu group
from kernel logs.

## Start guest virtual machine

With the device bind to vfio we can start Qemu and passthrough our example
device to Qemu virtual machine it with a command line argument. It actually does not matter
which vfio node id the device was assigned to earlier as long as all the
devices with the same vfio node are passed through and none of the devices
in the same group is left behind. The qemu command line argument for
passthrough used the pcie device id as identifier for the devices so each
device which is passed through needs its with its own qemu "-device" argument
as below.
```
-device vfio-pci,host="0001:01:00.0"
```

### Arm64 PCI device interrupts
Modern PCI devices use Message signaled interrupts (MSI) for limiting the need
for physical hardware interrupt pins. As passing through PCI or any devices is
fairly new to Qemu it seems Qemu does not have support for using MSI in arm64.
To get interrupts work in guest we need to tell kernel to disable MSI for our
passthrough device. One way to do this is to modify host device tree by
disabling MSI completely from the whole PCI bus. Easier method is to disable
MSI only from the guest by using "pci=nomsi" kernel argument with Qemu.
Disabling MSI is not required for X86 Qemu guest as it has support for
using MSI.

Notice that the command below is for aarch64 platform. The command works in a
test environment, but it is provided only as an example for passing through
a PCI device. It may require some changes in a real usage.

```
qemu-system-aarch64 \
    -nographic \
    -machine virt,accel=kvm \
    -cpu host \
    -m 1024 \
    -no-reboot \
    -kernel Image \
    -drive file=focal-server-cloudimg-arm64.raw,if=virtio,format=raw \
    -device vfio-pci,host=0001:01:00.0\
    -append "rootwait root=/dev/vda1 console=ttyAMA0 pci=nomsi"
```

### More work for Arm64 ###
The above is enough for X86 and also for ARM64 when using some simple or a bit
older PCIe devices. A bit more complex PCIe device which have larger internal
RAM pool need some modifications with Qemu sources. The problem with passing
through such devices is that the memory address range reserved for PCIe
devices is not large enough to map the internal memory of the PCI device. Some
graphics card have several gigabytes of internal ram which needs to be
accessible for virtual machine guest. The VIRT_PCIE_ECAM memory address range
in Qemu source code needs to be extended to allow mapping the whole PCIe device
memory range. In most cases a few gigabytes is sufficient.

```
diff --git a/hw/arm/virt.c b/hw/arm/virt.c
index ac626b3bef..d6fb597aee 100644
--- a/hw/arm/virt.c
+++ b/hw/arm/virt.c
@@ -161,9 +161,10 @@ static const MemMapEntry base_memmap[] = {
     [VIRT_SECURE_MEM] =         { 0x0e000000, 0x01000000 },
     [VIRT_PCIE_MMIO] =          { 0x10000000, 0x2eff0000 },
     [VIRT_PCIE_PIO] =           { 0x3eff0000, 0x00010000 },
-    [VIRT_PCIE_ECAM] =          { 0x3f000000, 0x01000000 },
+    /* ..Reserved 11Gb range for pcie = 11*1024*1024*1024b */
+    [VIRT_PCIE_ECAM] =          { 0x40000000, 0x2C0000000 },
     /* Actual RAM size depends on initial RAM and device memory settings */
-    [VIRT_MEM] =                { GiB, LEGACY_RAMLIMIT_BYTES },
+    [VIRT_MEM] =                { 0x300000000, LEGACY_RAMLIMIT_BYTES },
 };

```

After this modification Qemu needs to be compiled and installed to the host system.