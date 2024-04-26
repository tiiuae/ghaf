<!--
    Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
    SPDX-License-Identifier: CC-BY-SA-4.0
-->

# NVIDIA CSI-2 (Camera Serial Interface-2) Camera Support

NVIDIA Orin series devices add support for a high speed low latency and low CPU load camera interface MIPI CSI-2. This interface had speed and CPU load advantages over any USB camera where a USB camera has simple and easy integration compared to complex drivers of CSI-2. This interface provides 10 Gb/s over 
four image data lanes each 2.5 Gb/s. The software driver support requires V4l (video for linux). 

The CSI-2 interface includes i2c for camera control, a clock share, 4 image data lane and 2 additional GPIO for extra camera features. The clock synchronisation
allows high precision triggering between multiple cameras.

The problems with a CSI camera include bad drivers, device tree mapping issues. 
Drivers for every camera includes a complete replacement of the kernel configuration and override of kernel files and even some undocumented firmware is inserted in kernel through module structures. 

The method of integration of any camera driver requires extracting the camera kernel configuration differences from the Nvidia Orin series default kernel configuration. Later the changes to the kernel source needs to be examined to ensure it does not modify anything except v4l components and does not add anything except from the i2c driver files. 

The other problem is with the device tree where a manual mapping of multiple cameras to different CSI-2 lanes / ports is necessary as all drivers assume they connect to the first channel first port. 

Then a merged dtsi file is created as well as the kernel driver changes as two different patches with the configuration changes of the drivers are merged into StructuredKernelConfig options in the camera section of Ghaf. 

The initial camera integration includes a driver set for Toshiba TC358743 HDMI input chip and Alvium AVT 1800 camera mapped to different ports. 

A basic test procedure is as follows:

    Execute lsmod |grep avt_csi2 to see
    avt_csi2                     106496   0
    and lsmod |grep tc358743 to see
    tc358743                    49152   1
    Check if /dev/video0 (Toshiba) and /dev/video1 (Alvium) and /dev/media0 video4linux interface devices exist with
    ls -la /dev/video0 /dev/video1 /dev/media0
    install v4l-tools with
    nix-shell -p v4l-utils
    Execute `v4l-ctl --list-devices' in the nix-shell to see the below result.

NVIDIA Tegra Video Input Device (platformtegra-camrtc-ca):
               /dev/media0
ALVIUM 1800 C-158m 9-3c (platformtegra-capture-vi:0):
               /dev/video1
tc358743 10-000f (platformtegra-capture-vi:2):
               /dev/video0

Execute below commands to get more detailed information about resolution colorspace and formats:

v4l2-ctl -d /dev/video0 --list-formats-ext
v4l2-ctl -d /dev/video0 --list-ctrls-menus
v4l2-ctl --device /dev/video0 --stream-mmap
v4l2-ctl -d /dev/video1 --list-formats-ext
v4l2-ctl -d /dev/video1 --list-ctrls-menus
v4l2-ctl --device /dev/video1 --stream-mmap

And the --stream-mmap will show the data input from the capture device.
