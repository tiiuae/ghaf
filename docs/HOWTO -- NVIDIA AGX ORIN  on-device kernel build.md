# HOWTO -- NVIDIA AGX ORIN on kernel on-device development process


Nvidia is powerful device so developing and something lowlevel as drivers and passthroughs may be fast and efficient when done on board directly.


1. Preparational steps -- get a device, plug in monitor and keyboard (in most cases you need DP cable and monitor with DP socket, adapters DP-HDMI will not work before firmware update).
2. Boot and update onboard L4T ubuntu based linux distribution -- here are the link to the nvidia instructions -- .
3. Get a M.2 SSD nvme drive ( 512Gb or more is recommended ) and install it in the slot on the bottom of the device.
You'll have something like 
```
[    7.686537] nvme 0004:01:00.0: Adding to iommu group 11
[    7.691689] nvme nvme0: pci function 0004:01:00.0
[    7.696285] nvme 0004:01:00.0: enabling device (0000 -> 0002)
[    7.761026] nvme nvme0: 12/0/0 default/read/poll queues
[    7.780966]  nvme0n1: p1
```
in the logs after reboot

Create a partition table and a ext4 partition.
Mount the partition, copy the contents of the /home directory to the new drive.
Add a line to /etc/fstab so new drive is mounted as a /home:

/dev/nvme0n1p1 /home ext4 defaults 0 1

Reboot. 
Check if everything is ok and now you have a large new /home partition.

4. Get the Nvidia sources -- 	
https://developer.nvidia.com/embedded/l4t/r35_release_v1.0/release/jetson_linux_r35.1.0_aarch64.tbz2
https://developer.nvidia.com/embedded/l4t/r35_release_v1.0/sources/public_sources.tbz2

Unpack them

5. Nvidia has a complicated kernel build process and a special script to build the sources.
Under the ./Linux_for_Tegra/source/public/ is the script named ./nvbuild.sh that will assemble sources, add the default cnfig  and compile to the output directory.
Typicaly script is run as:
```
   $  ./nvbuild.sh -o $PWD/kernel_out
```
The result is stored in the ./kernel_out directory.

6. Default kernel is ./kernel/kernel-5.10/arch/arm64/configs/tegra_defconfig
7. I modified the ./nvbuild script adding an additional menuconfig phase so I can make slight modifications to the kernel config before  building:
```

        "${MAKE_BIN}" -C "${source_dir}" ARCH=arm64 \
                LOCALVERSION="-tegra" \
                CROSS_COMPILE="${CROSS_COMPILE_AARCH64}" \
                "${O_OPT[@]}" "${config_file}"

 +       "${MAKE_BIN}" -C "${source_dir}" ARCH=arm64 \
 +               LOCALVERSION="-tegra" \
 +               CROSS_COMPILE="${CROSS_COMPILE_AARCH64}" \
 +               "${O_OPT[@]}"  \
 +               --output-sync=target menuconfig
 +
        "${MAKE_BIN}" -C "${source_dir}" ARCH=arm64 \
                LOCALVERSION="-tegra" \
                CROSS_COMPILE="${CROSS_COMPILE_AARCH64}" \
                "${O_OPT[@]}" -j"${NPROC}" \
                --output-sync=target Image

```

8. To install build results I've developed another script, that installs kernel, modules and compiled DTBs in on the device:
```
./nvinstall.sh:

#!/bin/bash

# install kernel
pushd kernel_out && sudo make modules_install &&  sudo make install && popd

# install additional modules
pushd ~/RTL88x2BU-Linux-Driver/ && make && sudo make install && popd

# flash DTB
pushd kernel_out && \
sudo dd if=./arch/arm64/boot/dts/nvidia/tegra234-p3701-0000-p3737-0000.dtb of=/dev/mmcblk0p3 && \
sudo dd if=./arch/arm64/boot/dts/nvidia/tegra234-p3701-0000-p3737-0000.dtb of=/dev/mmcblk0p6 && \
popd
``

9. Root DTS for Nvidia Jetson ORIN is ./hardware/nvidia/platform/t23x/concord/kernel-dts/tegra234-p3701-0000-p3737-0000.dts. 

Please mind it is out of the kernel source tree! But it is recompiled every time you build the kernel.

10. Before installing the newly built kernel, update the bootloader config as in my example:
```
TIMEOUT 60
DEFAULT primary

MENU TITLE L4T boot options

LABEL primary
      MENU LABEL primary kernel
      LINUX /boot/vmlinuz-5.10.104-tegra
      INITRD /boot/initrd.img-5.10.104-tegra
      APPEND ${cbootargs} root=/dev/mmcblk0p1 rw rootwait rootfstype=ext4 mminit_loglevel=4 console=ttyTCU0,115200 console=tty0 firmware_class.path=/etc/firmware fbcon=map:0 net.ifnames=0 

 LABEL backup
    MENU LABEL backup kernel
    LINUX /boot/Image
    INITRD /boot/initrd
    APPEND ${cbootargs} root=/dev/mmcblk0p1 rw rootwait rootfstype=ext4 mminit_loglevel=4 console=ttyTCU0,115200 console=tty0 firmware_class.path=/etc/firmware fbcon=map:0 net.ifnames=0
```

So after ./nvinstall.sh you'll have your new kernel as primary and system default kernel as backup for emergency reasons.


Thats all for today :-)