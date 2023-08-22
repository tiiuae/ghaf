<!--
    Copyright 2022-2023 TII (SSRC) and the Ghaf contributors
    SPDX-License-Identifier: CC-BY-SA-4.0
-->

# Build and Run

This tutorial assumes that you already have basic [git](https://git-scm.com/) experience.

The canonical URL for the upstream Ghaf git repository is <https://github.com/tiiuae/ghaf>. To try Ghaf, you can build it from the source.

>[Cross-compilation](../ref_impl/cross_compilation.md) support is currently under development and not available for the building process.


## Prerequisites

First, follow the basic device-independent steps:

* Clone the git repository <https://github.com/tiiuae/ghaf>.
* Ghaf uses a Nix flake approach to build the framework targets, make sure to:
  * Install Nix or full NixOS if needed: <https://nixos.org/download.html>.
  * Enable flakes: <https://nixos.wiki/wiki/Flakes#Enable_flakes>.
    To see all Ghaf-supported outputs, type `nix flake show`.
  * Set up an AArch64 remote builder: <https://nixos.org/manual/nix/stable/advanced-topics/distributed-builds.html>.


Then you can use one of the following instructions for the supported targets:

| Device                  | Architecture     | Instruction      |
|---                      |---               | ---              |
| Virtual Machine | x86_64           | [Running Ghaf Image for x86 VM (ghaf-host)](./build_and_run.md#running-ghaf-image-for-x86-vm-ghaf-host)     |
| Generic x86 Сomputer | x86_64           | [Running Ghaf Image for x86 Computer](./build_and_run.md#running-ghaf-image-for-x86-computer) |
| Lenovo X1 Carbon Gen 11 | x86_64           | [Running Ghaf Image for Lenovo X1](./build_and_run.md#running-ghaf-image-for-lenovo-x1) |
| NVIDIA Jetson AGX Orin  | AArch64          | [Ghaf Image for NVIDIA Jetson Orin AGX](./build_and_run.md#ghaf-image-for-nvidia-jetson-orin-agx)     |
| NXP i.MX 8QM-MEK        | AArch64          | [Building Ghaf Image for NXP i.MX 8QM-MEK](./build_and_run.md#building-ghaf-image-for-nxp-imx-8qm-mek)     |
| MICROCHIP icicle-kit    | RISCV64          | [Building Ghaf Image for Microchip Icicle Kit](./build_and_run.md#building-ghaf-image-for-microchip-icicle-kit) |


---

## Running Ghaf Image for x86 VM (ghaf-host)

Before you begin, check device-independent [prerequisites](./build_and_run.md#prerequisites).

From the `ghaf` source directory, run the `nix run .#packages.x86_64-linux.vm-debug` command.

This creates `ghaf-host.qcow2` copy-on-write overlay disk image in your current directory. If you do unclean shutdown for the QEMU VM, you might get weird errors the next time you boot. Simply removing `ghaf-host.qcow2` should be enough. To cleanly shut down the VM, from the menu bar of the QEMU Window, click Machine and then Power Down.

---

## Running Ghaf Image for x86 Computer

Before you begin, check device-independent [prerequisites](./build_and_run.md#prerequisites).

Do the following:
1. To build the target image, run the command:
    ```
    nix build github:tiiuae/ghaf#generic-x86_64-debug
    ```
2. After the build is completed, prepare a USB boot media with the target image you built:
    ```
    dd if=./result/nixos.img of=/dev/<YOUR_USB_DRIVE> bs=32M
    ```
3. Boot the computer from the USB media.

---

## Running Ghaf Image for Lenovo X1

Lenovo X1 is the reference x86_64 device for the Ghaf project.

Do the following:
1. To build the target image, run the command:
    ```
    nix build github:tiiuae/ghaf#lenovo-x1-carbon-gen11-debug
    ```
2. After the build is completed, prepare a USB boot media with the target image you built:
    ```
    dd if=./result/nixos.img of=/dev/<YOUR_USB_DRIVE> bs=32M
    ```
3. Boot the computer from the USB media.

---

## Ghaf Image for NVIDIA Jetson Orin AGX

Before you begin:

* Check device-independent [prerequisites](./build_and_run.md#prerequisites).
* If you use a new device, [flash bootloader firmware](./build_and_run.md#flashing-nvidia-jetson-orin-agx) first. Then you can [build and run a Ghaf image](./build_and_run.md#building-and-running-ghaf-image-for-nvidia-jetson-orin-agx).


#### Flashing NVIDIA Jetson Orin AGX

1. Run the command:
    ```
    nix build github:tiiuae/ghaf#nvidia-jetson-orin-agx-debug-flash-script
    ```
    It will build the Ghaf image and bootloader firmware, and prepare the flashing script. Give "yes" answers to all script questions. The building process takes around 1,5 hours.

2. Set up the following connections:
   1. Connect the board to a power supply with a USB-C cable.
   2. Connect a Linux laptop to the board with the USB-C cable.
   3. Connect the Linux laptop to the board with a Micro-USB cable to use [serial interface](https://developer.ridgerun.com/wiki/index.php/NVIDIA_Jetson_Orin/In_Board/Getting_in_Board/Serial_Console).

   > For more information on the board's connections details, see the [Hardware Layout](https://developer.nvidia.com/embedded/learn/jetson-agx-orin-devkit-user-guide/developer_kit_layout.html) section of the Jetson AGX Orin Developer Kit User Guide.

3. After the build is completed, put the board in recovery mode. For more information, see the [Force Recovery](https://developer.nvidia.com/embedded/learn/jetson-agx-orin-devkit-user-guide/howto.html#force-recovery-mode) Mode section in the Jetson AGX Orin Developer Kit User Guide.

4. Run the flashing script:
    ```
    sudo ~/result/bin/flash-ghaf-host
    ```
    There is a time-out for this operation, so run the script within one minute after putting the device in recovery mode. If you got the error message "ERROR: might be timeout in USB write.":

      1. Reboot the device and put it in recovery mode again.
      2. Check with the `lsusb` command if your computer can still recognize the board, and run the flash script again.

5. Restart the device after flashing is done.


#### Building and Running Ghaf Image for NVIDIA Jetson Orin AGX

After the latest firmware is [flashed](./build_and_run.md#flashing-nvidia-jetson-orin-agx), it is possible to use a simplified process by building only the Ghaf disk image and running it from external media:

1. To build the target image, run the command:
    ```
    nix build github:tiiuae/ghaf#nvidia-jetson-orin-agx-debug
    ```
2. After the build is completed, prepare a USB boot media with the target image you built:
    ```
    dd if=./result/nixos.img of=/dev/<YOUR_USB_DRIVE> bs=32M
    ```
3. Boot the hardware from the USB media.

In the current state of Ghaf, it is a bit tricky to make NVIDIA Jetson Orin AGX boot Ghaf from a USB if the same thing has already been flashed on the boards's eMMC. To succeed, you can change partition labels on eMMC (or optionally wiping everything away by formatting):

1. Log in as a root:
    ```
    sudo su
    ```
2. Check the current labels:
    ```
    lsblk -o name,path,fstype,mountpoint,label,size,uuid
    ```
3. Change the ext4 partition label:
    ```
    e2label /dev/mmcblk0p1 nixos_emmc
    ```
4. Change the vfat partition label:
    ```
    dosfslabel /dev/mmcblk0p2 ESP_EMMC
    ```
5. Verify the labels that were changed:
    ```
    lsblk -o name,path,fstype,mountpoint,label,size,uuid
    ```
6. After these changes NVIDIA Jetson Orin AGX cannot boot from its internal eMMC. It will boot from the USB device with the correct partition labels.

---

## Building Ghaf Image for NXP i.MX 8QM-MEK

Before you begin, check device-independent [prerequisites](./build_and_run.md#prerequisites).

In the case of i.MX8, Ghaf deployment consists of creating a bootable SD card with a first-stage bootloader (Tow-Boot) and USB media with the Ghaf image:

1. To build and flash [**Tow-Boot**](https://github.com/tiiuae/Tow-Boot) bootloader:

    ```
    $ git clone https://github.com/tiiuae/Tow-Boot.git && cd Tow-Boot
    $ nix-build -A imx8qm-mek
    $ sudo dd if=result/ shared.disk-image.img of=/dev/<SDCARD>
    ```

2. To build and flash the Ghaf image:
   1. Run the `nix build .#packages.aarch64-linux.imx8qm-mek-release` command.
   2. Prepare the USB boot media with the target HW image you built: `dd if=./result/nixos.img of=/dev/<YOUR_USB_DRIVE> bs=32M`.

3. Insert an SD card and USB boot media into the board and switch the power on.

---


## Building Ghaf Image for Microchip Icicle Kit

Before you begin:

* Check device-independent [prerequisites](./build_and_run.md#prerequisites).
* Make sure HSS version 0.99.35-v2023.02 is programmed in your board eNVM. The version can be seen in the pre-bootloader log. Check the video guide to build HSS and program the eNVM: [How to build HSS and program the eNVM?](https://www.youtube.com/watch?v=McAt2-6cwd4) 

In the case of the Icicle Kit, Ghaf deployment consists of creating an SD image with U-Boot and Linux kernel from Microchip, and Ghaf-based NixOS rootfs:

1. Build a Ghaf SD image:

   a. Run the nix build .#packages.riscv64-linux.microchip-icicle-kit-release command to release the image.
   b. Run the nix build .#packages.riscv64-linux.microchip-icicle-kit-debug command to debug the image.

2. Flash the Ghaf SD image:

   * If you want to use a SD card:
     * Prepare the SD card with the target HW image you built: dd if=./result/nixos.img of=/dev/<YOUR_SD_DEVICE> bs=32M.
     * Insert an SD card into the board and switch the power on.

   * If you want to use the onboard MMC:
     * You can directly flash a NixOS image to onboard an MMC card: dd if=./result/nixos.img of=/dev/<YOUR_MMC_DEVICE> bs=32M.

For more information on how to access the MMC card as a USB disk, see [MPFS Icicle Kit User Guide](https://tinyurl.com/48wycdka).
