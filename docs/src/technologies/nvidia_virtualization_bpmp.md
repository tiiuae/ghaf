<!--
    Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
    SPDX-License-Identifier: CC-BY-SA-4.0
-->

# NVIDIA Jetson AGX Orin: Boot and Power Management Processor Virtualization

Boot and Power Management Processor (BPMP) is the NVIDIA processor, which is designed for booting process handling and offloading the power management, clock management, and reset control tasks from the CPU. 

The BPMP virtualization on the NVIDIA Jetson AGX Orin involves enabling VMs to access specific BPMP resources. This capability is crucial for passing through platform devices where control over resets and clocks configurations is required.


## Architectural Overview

* **Resource Access**: The BPMP virtualization allows VMs to access and manage resources such as device clocks and resets.
* **Foundation for Device Virtualization**: This setup lays the groundwork for future virtualization of more complex devices like GPUs.
* **Module Introduction**: A new `virtualization` module is introduced, divided into `common` and `host` modules with a plan to add a `guest` module for NixOS-based guests.
* **Device Tree Configurations**: Modifications are made with patching to support virtualization features.
* **Compatibility**: The current implementation supports a Ghaf host with an Ubuntu guest.


## Use Cases

The current implementation includes a host configuration for the UARTA passthrough as a test case demonstrating the practical application of the BPMP virtualization. At the same time, the current implementation still requires manually built Ubuntu guest. Work continues to integrate `microvm.nix` declared guest that supports NVIDIA BPMP virtualization with the UARTA passthrough demo. This work is generally important for future NVIDIA Jetson platform bus GPU passthrough. With this feature it is possible to virtualize the NVIDIA-Jetson-integrated GPU connected to the platform bus.


## Using BPMP Virtualization Options on NVIDIA Jetson AGX Orin

1. Enable NVIDIA BPMP virtualization on a Ghaf host for an NVIDIA Jetson-target using the following configuration options:

    ```nix
      hardware.nvidia = {
        virtualization.enable = true;
        passthroughs.uarta.enable = true;
    };
    ```

    > [!IMPORTANT]
    > These options are integrated to [NVIDIA Jetson Orin targets](https://github.com/tiiuae/ghaf/blob/main/targets/nvidia-jetson-orin/default.nix) but disabled by default until the implementation is finished.

2. Build the target and boot the image. You can write the image to an SSD for testing with a recent NVIDIA UEFI FW.


## Testing


### Host Testing

1. Check the `bpmp-host` device:

    ```
    [ghaf@ghaf-host:~]$ ls /dev | grep bpmp-host
    bpmp-host
    ```

2. Check that `vfio-platform` binding is successful:

    ```
    ghaf@ghaf-host:~]$ ls -l /sys/bus/platform/drivers/vfio-platform/3100000.serial
    lrwxrwxrwx 1 root root 0 Dec  8 08:26 /sys/bus/platform/drivers/vfio-platform/3100000.serial -> ../../../../devices/platform/3100000.serial
    ```


### Guest for UARTA Testing

> [!TIP]
> UARTA is an UART unit with a port A connection. For more information, see [UART Connections](nvidia_agx_pt_uart.md#uart-connections).

1. Build a guest kernel according to [UARTA passthrough instructions](https://github.com/jpruiz84/bpmp-virt)[^note1] and use the following script to start the VM:

    > [!IMPORTANT]
    > IMG is the kernel image and FS the rootfs.

    ```
    IMG=$1
    FS=$2

    qemu-system-aarch64 \
        -nographic \
        -machine virt,accel=kvm \
        -cpu host \
        -m 1G \
        -no-reboot \
        -kernel $IMG \
        -drive file=$FS,if=virtio,format=qcow2 \
        -net user,hostfwd=tcp::2222-:22 -net nic \
        -device vfio-platform,host=3100000.serial \
        -dtb virt.dtb \
        -append "rootwait root=/dev/vda console=ttyAMA0"
    ```

2. With UARTA connected start Minicom on the working machine:

    ```
    minicom -b 9600 -D /dev/ttyUSB0
    ```

3. Test UARTA by echoing a string to the correct `tty` in the VM:

    ```
    echo 123 > /dev/ttyTHS0
    ```


## Related Topics

[NVIDIA Jetson AGX Orin: UART Passthrough](./nvidia_agx_pt_uart.md#nvidia-jetson-agx-orin-uart-passthrough)



[^note1]: That documentation is in the [bpmp-virt](https://github.com/jpruiz84/bpmp-virt) side repository, as that approach does not use microvm.
