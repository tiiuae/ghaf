 <!--
    Copyright 2022-2023 TII (SSRC) and the Ghaf contributors
    SPDX-License-Identifier: CC-BY-SA-4.0
-->

# NVIDIA Jetson AGX Orin: PCIe passthrough

This document describes the PCIe passthrough implementations on the NVIDIA Jetson AGX Orin board. The goal of this document is to give an overview of passing through different PCIe devices and the limitations of PCIe in the board.


##  PCIe Slots in NVIDIA Jetson AGX Orin

There are two (or actually three) PCIe slots in the Jetson AGX Orin board:

* One of the connectors is a [full-size PCIe 8x slot](#full-size-pcie-slot) located under a black plastic cover above the micro USB serial debug port on the side of the board.
* The other slot is a [smaller M.2 slot](#pcie-m2-slot) that is located at the bottom of the board. By default, the slot is in use of the included Wi-Fi and Bluetooth module.
* The third slot is actually an [NVMe slot](#pcie-m2-nvme-2247-for-ssd) which can be used to add an NVMe SSD to the board.

> For more information on the board's connections details, see the [Hardware Layout](https://developer.nvidia.com/embedded/learn/jetson-agx-orin-devkit-user-guide/developer_kit_layout.html) section of the Jetson AGX Orin Developer Kit User Guide.

When using one of the slots:

* First and foremost, always turn off and disconnect any power sources from the board and its peripherals when connecting or disconnecting devices to any of the PCIe buses connect.
* When adding or removing devices to the board, there is always a risk of setting off an electrical discharge in one of the components which may damage the connected device or the board itself.


#### Full-Size PCIe Slot

The full-size PCIe connector is under the black plastic cover on one of the sides of the device. The cover is held in place with a fairly strong magnet. There is a small connector ribbon and a few delicate wires going from the board internals to a Wi-Fi antenna on the cover.

> **TIP:** Make sure to remove the cover carefully for not ripping the whole cover off along with the antenna cables.

The PCIe slot is simular to one inside a desktop computer. One key difference: the Jetson AGX Orin board has limited 12V power output capabilities and can only output a maximum of 40W power to its PCIe slot. Regular desktop PCIe slot can output 75W at 12V so some more power-hungry PCIe cards [^note1] may not work with the Jetson AGX Orin board. There may also be a risk of damaging the board if a card tries to pull too much power from the PCIe socket.

> **TIP:** We recommend to check carefully the power requirements of a device before turning the device on.

A good rule of thumb might be if the device has a cooler to actively cool it down then some care should be taken before starting to use the card. Some trials have been done with GPU devices that use at maximum 30-34W power. The devices seem to work well in Jetson AGX Orin, but it is difficult to say how much power the card actually pulls from the slot at any given time. No real performance or stress tests have been done but under usual GUI and simple 3d application usage the cards (NVIDIA Quadro P1000 and NVIDIA Quadro T600) seem to work fine.


#### PCIe M.2 Slot

The PCIe M.2 slot with key type A+E is at the bottom of the board. By default, this slot is in use of the internal Wi-Fi and Bluetooth card. There are different types of M.2 slots all of which are not compatible with one another. The slot in Jetson AGX Orin is type A+E, and it supports PCIe 2x and USB transport buses.


#### PCIe M.2 NVMe for SSD

The third slot is M.2 NVMe 2280 (22 mm width and 80 mm length) and can be used for NVMe SSD. Passing through this interface has not been tested as the SSD is in most cases used by the host.


## Enabling PCIe Devices for VFIO

As in the [UART Passthrough](nvidia_agx_pt_uart.md), the default device tree requires some modifications.

With the default configuration, the PCI devices are set to the same VFIO group as the PCI bus itself. The trouble here is that the PCI bus is a platform bus device which is a bit tricky to pass through to the guest. It is possible to pass through only the individual PCI devices and not the whole bus.

To pass through individual PCI devices one by one, set the devices in their individual VFIO groups or remove the PCI bus from the same VFIO group:

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


### Binding Device for VFIO

To set up the device for VFIO, unload the device driver and then replac it with the `vfio-pci` driver.

The example below can be used for a device in the PCI bus `0001`.  
The device `0001:01:00.0` in the first bus is the Jetson AGX Orin board with the M.2 Wi-Fi card. The full size PCI bus id is `0005`. It is possible that a single PCI card contains multiple devices. In that case, all the devices need to be passed through together as they are in the same VFIO group. Usually the graphics card also contains some sound output device as a separate device.

```
export DEVICE="0001:01:00.0"
export VENDOR_ID=$(cat /sys/bus/pci/devices/$DEVICE/vendor)
export DEVICE_ID=$(cat /sys/bus/pci/devices/$DEVICE/device)

echo "$DEVICE" > /sys/bus/pci/devices/$DEVICE/driver/unbind

echo "$VENDOR_ID $DEVICE_ID" > /sys/bus/pci/drivers/vfio-pci/new_id
```

In case of success, this device is bound to VFIO. The VFIO nodes are usually owned by the root and in some cases may be group accessible by the VFIO group. To use the VFIO devices, the user who starts QEMU needs access to the VFIO device node:

```
# List of vfio device <id> nodes
ls /dev/vfio/

# List of devices within each iommu group
ls /sys/kernel/iommu_groups/<id>/devices/
```

You can also check the kernel logs to know which device belongs to which VFIO IOMMU group.


## Starting Guest VM

After binding a device to VFIO, you can access the device in a VM. To do so, use a command line argument (as in the example) for the PCI device to pass through to QEMU.

> It does not matter which VFIO node ID was assigned to the device earlier, as long as all the devices with the same VFIO node are passed through, and none of the devices in the same group is left behind.

The QEMU command line argument for passthrough uses the PCIe device ID as identifier for the devices. Each
device which is passed through needs its own QEMU `-device` argument as below:

```
-device vfio-pci,host="0001:01:00.0"
```


### ARM64 PCI Device Interrupts

Modern PCI devices use the Message Signaled Interrupts (MSI) method to limit the need for physical hardware interrupt pins. As passing through PCI or any other devices is fairly new to QEMU, it seems MSI in ARM64 is not supported by QEMU [^note2].

To get interrupts to work in the guest, we need to signal the kernel to disable MSI for our passthrough device. There are two ways of doing it:

1. To modify the host device tree by disabling MSI completely from the whole PCI bus.
2. To disable MSI only from the guest by using the `pci=nomsi` kernel argument with QEMU. Disabling MSI is not required for the x86 QEMU guest as it has MSI support.

The command below is provided only as a test example for passing through a PCI device for AArch64 [^note3]:

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


### More Work for ARM64

The information above is enough for x86 and also for ARM64 processor architecture when using some simple or a bit older PCIe devices. A bit more complex PCIe device which has a larger internal RAM pool needs some modifications with QEMU sources.

The problem with passing through such devices is that the memory address range reserved for PCIe devices is not large enough to map the internal memory of the PCI device. Some graphics cards have several gigabytes of internal RAM which needs to be accessible for the VM guest.

You can extend the VIRT_PCIE_ECAM memory address range in the QEMU source code to allow mapping the whole PCIe device memory range. In most cases a few gigabytes is sufficient:

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

After these changes, compile QEMU and install it on the host system.

[^note1]: An example of a power-hungry card is a graphics accelerator card.

[^note2]: Our approach of using ARM as a VM host with passthroughs fairly new so it is hard to search for help or references online, but this bug [qemu-system-aarch64 error](https://bugs.launchpad.net/ubuntu/+source/libvirt/+bug/1832394) seems to be close enough. The main hint of MSI not being fully supported yet by QEMU on ARM64 comes from the case when the device starts working only with MSI disabled from the guest kernel argument.

[^note3]: It may require some changes for real usage.