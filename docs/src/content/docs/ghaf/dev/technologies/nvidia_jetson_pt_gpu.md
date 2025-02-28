<!--
    Copyright 2022-2025 TII (SSRC) and the Ghaf contributors
    SPDX-License-Identifier: CC-BY-SA-4.0
-->

# NVIDIA Jetson: GPU Passthrough

This document describes how to passthrough the NVIDIA Jetson GPU to a QEMU/KVM
virtual machine.

# Requirements brief

This list summarizes the requirements for GPU passthrough:

1. NVIDIA Jetpack 6.2 (36.4.3) with Linux kernel 5.15
2. QEMU 9.2 with BPMP and 1:1 mmio mapping patches
3. BPMP proxy patch for Linux Kernel
4. Host device tree with dummy drivers and IOMMUs groups
5. Guest VM device tree with BPMP virt and passthrough devices
6. Host bash script to bind the passthrough devices to vfio-platform driver
7. Host bash script to launch QEMU with the passthrough devices

All of these requirements are explained in depth in the following sections.

# BPMP virtualization

The BPMP (Boot and Power Management Processor) virtualization allows virtual
machines (VMs) to access the BPMP resources (such as specific devices' clocks,
resets, and power) to passthrough platform devices where the drivers require
control of resets, clocks, and power configurations.

The next diagram shows on the left how the GPU or UART drivers on host
communicate with the BPMP driver to enable the reset and clocks to init the
device. Since NVIDIA does not support a mailbox passthrough to communicate a VM
directly to the BPMP, we need to virtualize the BPMP services. We have found
that the reset and clock transactions are done in the BPMP driver with a common
function called **tegra_bpmp_transfer**. Therefore, to virtualize the BPMP, we
will virtualize this function.

                                  VM
                                   +------------------+
                                   |GPU or UART driver|
                                   +------------------+
                                             | Reset/clocks
                                             v
                                    +------------------+
                                    | BPMP guest proxy |
                                    +------------------+
                                  -----------|-----------
                                  VMM/Qemu   v
                                   +------------------+
                                   |   BPMP VMM guest |
                                   +------------------+
                                  -----------|-----------
    Host                          Host       v
     +------------------+           +-----------------+
     |GPU or UART driver|           | BPMP host proxy |
     +------------------+           +-----------------+
               | Reset/clocks                |
               v                             v
       +--------------+              +--------------+
       | BPMP driver  |              | BPMP driver  |
       +--------------+              +--------------+


## General design assumptions

1. We can use the same kernel image for guest and host, with the same kernel
   configuration. The enables come from the device tree.
2. Minimal modifications to kernel bpmp source code.
3. Add another repository for BPMP proxy (host and guest) as kernel overlay.


## BPMP host proxy

- Runs in the host kernel. It exposes the tegra_bpmp_transfer function to the
  user level via a char device "/dev/bpmp-host".
- Written as a builtin kernel module overlay in this repository.
- Enabled in the kernel via a "*nvidia,bpmp-host-proxy*" device tree node on the
  host device tree.
- In the "nvidia,bpmp-host-proxy" device tree node, define the clocks and resets
  that will be allowed to be used by the VMs.
- The implementation is done in the patch:
  [0001-Add-bpmp-virt-kernel-modules-for-kernel-5.15.patch](../../../modules/reference/hardware/jetpack/nvidia-jetson-orin/virtualization/common/bpmp-virt-common/patches/0001-Add-bpmp-virt-kernel-modules-for-kernel-5.15.patch)


## BPMP VMM/QEMU guest

- Communicates the BPMP-host to the BPMP-guest through a IOMEM in the VMM/Qemu.
- The implementation is done in the patch:
  [0001-nvidia-bpmp-guest-driver-initial-commit.patch](../../../modules/reference/hardware/jetpack/nvidia-jetson-orin/virtualization/host/bpmp-virt-host/overlays/qemu/patches/0001-nvidia-bpmp-guest-driver-initial-commit.patch)


## BPMP guest proxy

- Runs in the guest kernel. It intercepts tegra_bpmp_transfer call and routes
  the request through proxies to the host kernel driver.
- Written as a builtin kernel module overlay in this repository.
- Enable it with the "*virtual-pa*" node in the bpmp node on the guest device
  tree.
- The *virtual-pa* contains the QEMU assigned VPA (Virtual Physical Address) for
  BPMP VMM guest.
- The implementation is done in the patch:
  [0001-Add-bpmp-virt-kernel-modules-for-kernel-5.15.patch](../../../modules/reference/hardware/jetpack/nvidia-jetson-orin/virtualization/common/bpmp-virt-common/patches/0001-Add-bpmp-virt-kernel-modules-for-kernel-5.15.patch)


## BPMP driver

The BPMP driver has small modifications intended to:
- Intercept the tegra_bpmp_transfer function to use the
  tegra_bpmp_transfer_redirect from the BPMP guest.
- Read the *virtual-pa* node from the guest device tree to pass the BPMP VMM
  guest VPA to the BPMP guest proxy module.

- The implementation is done in the patch:
  [0001-Add-bpmp-virt-kernel-modules-for-kernel-5.15.patch](../../../modules/reference/hardware/jetpack/nvidia-jetson-orin/virtualization/common/bpmp-virt-common/patches/0001-Add-bpmp-virt-kernel-modules-for-kernel-5.15.patch)

## Kernel configurations:

Add these kernel configurations to enable the BPMP host and guest proxy in the
Linux kernel:

        CONFIG_TEGRA_BPMP_GUEST_PROXY=y
        CONFIG_TEGRA_BPMP_HOST_PROXY=y


## Device tree

1. For the host, add the bpmp_host_proxy node:

    ```java
        bpmp_host_proxy: bpmp_host_proxy {
            compatible = "nvidia,bpmp-host-proxy";
            allowed-clocks = <TEGRA234_CLK_UARTA
                            TEGRA234_CLK_PLLP_OUT0>;
            allowed-resets = <TEGRA234_RESET_UARTA>;
            status = "okay";
        };
    ```

    With this configuration, we enable the bpmp-host in the host. Also, here we
    inform the bpmp-host which are the allowed resources (clocks and resets)
    that can be used by the VMs. Copy these resources from the device tree node
    of the devices that you will passthrough.

    **Note:** You can also define the allowed power domains that are needed by
    some devices like the GPU:

          allowed-power-domains = <TEGRA234_POWER_DOMAIN_DISP
                    TEGRA234_POWER_DOMAIN_GPU>;

    For debugging purposes, you can enable permissions to all domains by
    applying this patch:
    [0002-Bpmp-host-allows-all-domains.patch](../../../modules/reference/hardware/jetpack/nvidia-jetson-orin/virtualization/common/bpmp-virt-common/patches/0002-Bpmp-host-allows-all-domains.patch)

2. For the guest, you will need to add to the guest's device tree root the bpmp
   with the Qemu bpmp guest VPA:

    ```java
            bpmp: bpmp {
                compatible = "nvidia,tegra234-bpmp", "nvidia,tegra186-bpmp";
                virtual-pa = <0x0 0x090c0000>;
                #clock-cells = <1>;
                #reset-cells = <1>;
                #power-domain-cells = <1>;
                status = "okay";
            };
    ```

    Here you tell the bpmp-guest which is the VPA (virtual-pa), that in this
    case is 0x090c0000.

# Devices required to enable GPU and display passthrough

For GPU and display passthrough, we need to passthrough and virtualize the
following devices and memory regions:

1. **BPMP**: The BPMP (Boot and Power Management Processor) is a unit that
   enables clocks, resets, and power to all the platform devices. This unit
   cannot be passed through to the VM because many devices such as CPU, memory
   controllers, and others use this in the host. For this reason, we have to
   virtualize this unit by creating a BPMP proxy in the Host, VMM/QEMU, and in
   the Guest.

2. **GPU and Display devices:** This is the list of devices that we need to
   passthrough to support GPU and display in the VM:

   - GPU: gpu@17000000
   - Host1x: host1x@13e00000
   - JPG accelerator: nvjpg@15540000
   - Display Controller Engine (DCE): dce@d800000
   - Display: display@13800000

3. **CMA regions:** Continuous Memory Allocator (CMA) regions are needed by the
   GPU and display devices for DMA operations and GPU VRAM memory. These are the
   regions that we are passing through from Host to Guest:

   - General CMA: vm_cma@80000000
   - GPU VRAM CMA: vm_cma_vram@100000000
   - Host1x Sync point: vm_hs@60000000

More information about these devices passthrough can be found in the host device
tree overlay:
[gpu_passthrough_overlay.dts](../../../modules/microvm/virtualization/microvm/gpuvm_res/gpu_passthrough_overlay.dts)


# Memory mapping:

The QEMU/KVM process runs mostly like a normal Linux user program. It allocates
its memory with normal malloc() or mmap() calls. If a guest is going to have 1GB
of physical memory, QEMU/KVM will effectively do a malloc(1<<30), allocating 1GB
of host virtual space. However, just like a normal program doing a malloc(),
there is no actual physical memory allocated at the time of the malloc().

The GPU and display controller drivers need a memory region with a specific and
known base address in the host physical memory. The physical base address of the
virtual memory in the VM could be known through the IOMMU, but at this moment
KVM is not supporting this automatic translation well. For this reason, we use
the VFIO platform to passthrough CMA (Contiguous Memory Allocation) regions to
the VM.

## Host memory reserved regions

The next table describes the memory regions reserved in the host for the Guest
VM:

|      Host memory region     | Base address |     Size    | Size MB |
|:---------------------------:|:------------:|:-----------:|:-------:|
| General CMA, vm_cma_p       |   0x80000000 |  0x30000000 |     768 |
| GPU VRAM CMA, vm_cma_vram_p |  0x100000000 | 0x100000000 |    4096 |
| Host1x Sync point, vm_hs_p  |   0x60000000 |  0x04000000 |      64 |


Not all drivers support the DMA memory translation that we can describe in the
device tree through the *dma-ranges* property. For this reason, a 1:1 mapping of
these regions allows us a more transparent passthrough implementation. To
achieve this, we created a patch in QEMU to add a parameter in the vfio-platform
device definition. This parameter is called *mmio-base* and it defines the base
start address to be assigned to a vfio-platform device. For this reason, when we
passthrough the memory regions to the Guest VM, we define this parameter in the
QEMU command as follows:

    -device vfio-platform,host=60000000.vm_hs_p,mmio-base=0x60000000 \
    -device vfio-platform,host=80000000.vm_cma_p,mmio-base=0x80000000 \
    -device vfio-platform,host=100000000.vm_cma_vram_p,mmio-base=0x100000000 \

This patch enables in QEMU the 1:1 memory region mapping through the *mmio-base*
parameter and increases the VFIO platform bus size from 32MB to 130GB:
[0004-vfio-platform-Add-mmio-base-property-to-define-start.patch](../../../modules/reference/hardware/jetpack/nvidia-jetson-orin/virtualization/host/bpmp-virt-host/overlays/qemu/patches/0004-vfio-platform-Add-mmio-base-property-to-define-start.patch)



## Guest VM memory regions

The next table describes the memory regions defined in the Guest VM:


|     Host memory    | Base address |     Size    | Size MB |
|:------------------:|:------------:|:-----------:|:-------:|
| linux,cma          |   0x88000000 |  0x04000000 |      64 |
| nvgpu_dma_carveout |   0x80000000 |  0x08000000 |     128 |
| vpr-carveout       |   0x8C000000 |  0x01000000 |      16 |
| fsi-carveout       |   0x8D000000 |  0x01000000 |      16 |
| vidmem_reserved    |   0x90000000 |  0x08000000 |     128 |
| gpu_reserved       |   0x98000000 |  0x08000000 |     128 |
| generic_reserved   |  0x100000000 | 0x100000000 |    4096 |

### linux,cma
This region is the Linux default CMA region, used for the devices that do not
have a dedicated CMA for them. For instance, the Display Controller Engine (DCE)
uses it.

### nvgpu_dma_carveout

This is the dedicated CMA region for GPU operations, such as uploading the
firmware to the GPU microcontrollers. This region is hardcoded in the patch for
the NVIDIA GPU driver, see
[0001-gpu-add-support-for-passthrough.patch](../../../modules/microvm/virtualization/microvm/gpuvm_res/0001-gpu-add-support-for-passthrough.patch),
line 54. One of the TODOs here is to modify the patch in order to read the
allocation address and size from the device tree.

### vpr, fsi, vidmem, and gpu_reserved regions

These regions are not used right now, but were added to have the full
definitions of the carveouts regions on the tegra-carveouts. Probably these
regions will be used by the hardware accelerators.

```java
	// Define the carveouts regions for the carveouts driver
	tegra-carveouts {
		compatible = "nvidia,carveouts";
		memory-region = <&generic_reserved &vpr &fsi_reserved &vidmem_reserved &gpu_reserved>;
		status = "okay";
	};
```

### generic_reserved

By default in the tegra carveouts driver, we can define up to 5 memory regions.
The 5th memory region is reserved for the GPU VRAM as shown in this section of
the source code from
*Linux_for_Tegra/source/nvidia-oot/drivers/video/tegra/nvmap/nvmap_init.c*

```c
    static struct nvmap_platform_carveout nvmap_carveouts[] = {
        [0] = {
            .name		= "generic-0",
            .usage_mask	= NVMAP_HEAP_CARVEOUT_GENERIC,
            .base		= 0,
            .size		= 0,
            .dma_dev	= &tegra_generic_dev,
            .cma_dev	= &tegra_generic_cma_dev,
    #ifdef NVMAP_CONFIG_VPR_RESIZE
            .dma_info	= &generic_dma_info,
    #endif
        },
        [1] = {
            .name		= "vpr",
            .usage_mask	= NVMAP_HEAP_CARVEOUT_VPR,
            .base		= 0,
            .size		= 0,
            .dma_dev	= &tegra_vpr_dev,
            .cma_dev	= &tegra_vpr_cma_dev,
    #ifdef NVMAP_CONFIG_VPR_RESIZE
            .dma_info	= &vpr_dma_info,
    #endif
            .enable_static_dma_map = true,
        },
        [2] = {
            .name		= "vidmem",
            .usage_mask	= NVMAP_HEAP_CARVEOUT_VIDMEM,
            .base		= 0,
            .size		= 0,
            .disable_dynamic_dma_map = true,
            .no_cpu_access = true,
        },
        [3] = {
            .name		= "fsi",
            .usage_mask	= NVMAP_HEAP_CARVEOUT_FSI,
            .base		= 0,
            .size		= 0,
        },
        [4] = {
            .name		= "gpu",
            .usage_mask	= NVMAP_HEAP_CARVEOUT_GPU,
            .base		= 0,
            .size		= 0,
        },
        ...
    };
```

Then *generic_reserved* region in the 5th region (4 space from 0) as the VRAM
for the GPU.

**NOTE:** By default in a native host configuration, the 5th space is not
defined in the tegra carveouts, so the GPU will use the shared unified memory
with the CPU.

**NOTE 2:** If you define these memory regions in the host to test a dedicated
memory region for the GPU VRAM, this will not work, because by default the UEFI
adds a tegra-carveouts node with only 2 regions that are passed from UEFI to the
Linux drivers.


# Guest device tree

The Guest device tree is based on the device tree extracted from QEMU virt
machine (*-M virt*). To get the base Qemu device tree, you can run the following
command:

    qemu-system-aarch64 \
        -nographic \
        -machine virt,accel=kvm,virt.dtb \
        -cpu host \
        -smp 4 \
        -m 4G \
        -enable-kvm

**Important note:** It is very important to regenerate this device tree if you
change the number of CPUs (*smp* parameter), because the virtual CPUs are
defined here for the Guest OS.

Then you must add the memory regions and the passthrough devices. This is
already done in the gpu-vm device tree:
[tegra234-gpuvm.dts](../../../modules/microvm/virtualization/microvm/gpuvm_res/tegra234-gpuvm.dts)

This GPU VM device tree has a *ranges* property in the node
*platform-bus@70000000*. The ranges property helps translate the address from
the device node definition to the address assigned by QEMU. In this way, you can
copy the device node from the original device tree provided by NVIDIA to this
section, without modifying the *regs* property of each device but setting up the
address translation in the common *ranges* property. To know which guest
physical address QEMU has assigned to each device, you can run this command in
the QEMU console:

    info -f mtree

The interrupts of each device are remapped by QEMU also. To know which interrupt
was assigned to each device, you can apply this QEMU patch
[0003-Print-irqs.patch](../../../modules/reference/hardware/jetpack/nvidia-jetson-orin/virtualization/host/bpmp-virt-host/overlays/qemu/patches/0003-Print-irqs.patch)

# Prepare and launch scripts

We will passthrough these memory regions and devices to the Guest VM:

- /sys/bus/platform/devices/100000000.vm_cma_vram_p
- /sys/bus/platform/devices/60000000.vm_hs_p
- /sys/bus/platform/devices/80000000.vm_cma_p
- /sys/bus/platform/devices/17000000.gpu
- /sys/bus/platform/devices/13e00000.host1x_pt
- /sys/bus/platform/devices/15340000.vic
- /sys/bus/platform/devices/15480000.nvdec
- /sys/bus/platform/devices/15540000.nvjpg
- /sys/bus/platform/devices/d800000.dce
- /sys/bus/platform/devices/13800000.display


We are passing through some hardware accelerators (vic, nvdec, nvjpg) because
nvjpg is needed in order for GPU interrupts to work (we don't know why). Also,
we are passing through vic and nvdec, because we were doing tests with them, and
if we remove them, we would need to update the address translations and
interrupts of the other devices.

These commands will bind the passthrough devices to the vfio-platform driver:

    echo vfio-platform > /sys/bus/platform/devices/80000000.vm_cma_p/driver_override
    echo vfio-platform > /sys/bus/platform/devices/17000000.gpu/driver_override
    echo vfio-platform > /sys/bus/platform/devices/13e00000.host1x_pt/driver_override
    echo vfio-platform > /sys/bus/platform/devices/15340000.vic/driver_override
    echo vfio-platform > /sys/bus/platform/devices/15480000.nvdec/driver_override
    echo vfio-platform > /sys/bus/platform/devices/15540000.nvjpg/driver_override
    echo vfio-platform > /sys/bus/platform/devices/d800000.dce/driver_override
    echo vfio-platform > /sys/bus/platform/devices/13800000.display/driver_override
    echo vfio-platform > /sys/bus/platform/devices/100000000.vm_cma_vram_p/driver_override
    echo vfio-platform > /sys/bus/platform/devices/60000000.vm_hs_p/driver_override

    echo 80000000.vm_cma_p > /sys/bus/platform/drivers/vfio-platform/bind
    echo 17000000.gpu > /sys/bus/platform/drivers/vfio-platform/bind
    echo 13e00000.host1x_pt > /sys/bus/platform/drivers/vfio-platform/bind
    echo 15340000.vic > /sys/bus/platform/drivers/vfio-platform/bind
    echo 15480000.nvdec > /sys/bus/platform/drivers/vfio-platform/bind
    echo 15540000.nvjpg > /sys/bus/platform/drivers/vfio-platform/bind
    echo d800000.dce > /sys/bus/platform/drivers/vfio-platform/bind
    echo 13800000.display > /sys/bus/platform/drivers/vfio-platform/bind
    echo 100000000.vm_cma_vram_p > /sys/bus/platform/drivers/vfio-platform/bind
    echo 60000000.vm_hs_p > /sys/bus/platform/drivers/vfio-platform/bind

You can confirm a successful binding by running this command:

    ls -lah /sys/bus/platform/drivers/vfio-platform

This command will launch QEMU with the devices and memory regions to
passthrough:

    qemu-system-aarch64 \
        -nographic \
        -machine virt,accel=kvm \
        -cpu host \
        -smp 4 \
        -m 4G \
        -no-reboot \
        -kernel ./Image \
        -drive file=rootfs_ubuntu_44gb.img.raw,if=virtio,format=raw \
        -dtb tegra234-p3768-0000+p3767-0000-nv_vm.dtb \
        -device vfio-platform,host=60000000.vm_hs_p,mmio-base=0x60000000 \
        -device vfio-platform,host=80000000.vm_cma_p,mmio-base=0x80000000 \
        -device vfio-platform,host=100000000.vm_cma_vram_p,mmio-base=0x100000000 \
        -device vfio-platform,host=17000000.gpu \
        -device vfio-platform,host=13e00000.host1x_pt \
        -device vfio-platform,host=15340000.vic \
        -device vfio-platform,host=15480000.nvdec \
        -device vfio-platform,host=15540000.nvjpg \
        -device vfio-platform,host=d800000.dce \
        -device vfio-platform,host=13800000.display \
        -append "rootwait root=/dev/vda console=ttyAMA0 loglevel=7 debug clk_ignore_unused pd_ignore_unused"


# Ghaf implementation

The [gpuvm.nix](../../../modules/microvm/virtualization/microvm/gpuvm.nix) has
all the configuration required to run a VM with NVIDIA GPU passthrough. You will
need only to enable it on [nvidia
flake-module](../../../targets/nvidia-jetson-orin/flake-module.nix)

```c
              hardware.nvidia = {
                virtualization.enable = true;
                virtualization.host.bpmp.enable = true;
                passthroughs.host.uarta.enable = false;
                # TODO: uarti passthrough is currently broken, it will be enabled
                # later after a further analysis.
                passthroughs.uarti_net_vm.enable = false;
              };

              virtualization = {
                microvm-host = {
                  enable = true;
                  networkSupport = true;
                };

                microvm = {
                  netvm = {
                    enable = true;
                    extraModules = netvmExtraModules;
                  };
                  gpuvm = {
                    enable = true;
                  };
```

Remember to enable *virtualization.host.bpmp.enable = true;* that is needed by
the gpu-vm.


# Create Ubuntu Linux kernel image and rootfs for the Guest VM

Additionally, you can create an Ubuntu Linux kernel image and rootfs for the
Guest VM. Follow these steps in Ubuntu 22.04:

1. Install the required packages:

        sudo apt-get install libssl-dev git qemu

2. Download and extract the GCC:

        wget https://developer.nvidia.com/downloads/embedded/l4t/r36_release_v3.0/toolchain/aarch64--glibc--stable-2022.08-1.tar.bz2

    Extract to *$HOME/l4t-gcc*

        tar -xvf aarch64--glibc--stable-2022.08-1.tar.bz2 -C $HOME/l4t-gcc

    Add to your env variables:

        export CROSS_COMPILE=$HOME/l4t-gcc/aarch64--glibc--stable-2022.08-1/bin/aarch64-buildroot-linux-gnu-


3. Download the Jetson Linux 36.4.3 that is part of JetPack 6.2

        wget https://developer.nvidia.com/downloads/embedded/l4t/r36_release_v4.3/release/Jetson_Linux_r36.4.3_aarch64.tbz2
        wget https://developer.nvidia.com/downloads/embedded/l4t/r36_release_v4.3/release/Tegra_Linux_Sample-Root-Filesystem_r36.4.3_aarch64.tbz2

        sudo tar xpf Jetson_Linux_r36.4.3_aarch64.tbz2

4. Synchronize all sources to the tag jetson_36.4.3:

        cd Linux_for_Tegra/source/
        ./source_sync.sh -k jetson_36.4.3

5. Edit
   Linux_for_Tegra/source/kernel/kernel-jammy-src/arch/arm64/configs/defconfig
   to add:

        CONFIG_TEGRA_BPMP_GUEST_PROXY=y
        CONFIG_TEGRA_BPMP_HOST_PROXY=y
        CONFIG_VFIO_PLATFORM=y

6. Apply the NVIDIA modules patches:

    Copy these patches to Linux_for_Tegra/source/

    - [0001-gpu-add-support-for-passthrough.patch](../../../modules/microvm/virtualization/microvm/gpuvm_res/0001-gpu-add-support-for-passthrough.patch)
    - [0002-Add-support-for-gpu-display-passthrough.patch](../../../modules/microvm/virtualization/microvm/gpuvm_res/0002-Add-support-for-gpu-display-passthrough.patch)
    - [0003-Add-support-for-display-passthrough.patch](../../../modules/microvm/virtualization/microvm/gpuvm_res/0003-Add-support-for-display-passthrough.patch)

    Apply these patches:

        patch -p1 < 0001-gpu-add-support-for-passthrough.patch
        patch -p1 < 0002-Add-support-for-gpu-display-passthrough.patch
        patch -p1 < 0003-Add-support-for-display-passthrough.patch

7. Apply the Linux kernel patch:

    Copy this patch to Linux_for_Tegra/source/kernel/kernel-jammy-src

    - [0001-tegra-fixed-chip-id.patch](../../../modules/microvm/virtualization/microvm/gpuvm_res/0001-tegra-fixed-chip-id.patch)

    Apply this patch:

        patch -p1 < 0001-tegra-fixed-chip-id.patch

8. Apply the BPMP patch:

    Copy this patch to Linux_for_Tegra/source/kernel/kernel-jammy-src

    - [0001-Add-bpmp-virt-kernel-modules-for-kernel-5.15.patch](../../../modules/reference/hardware/jetpack/nvidia-jetson-orin/virtualization/common/bpmp-virt-common/patches/0001-Add-bpmp-virt-kernel-modules-for-kernel-5.15.patch)

    Apply the patch:

        patch -p1 < 0001-Add-bpmp-virt-kernel-modules-for-kernel-5.15.patch


9. Build kernel and modules:

    In Linux_for_Tegra/source run:

        ./nvbuild.sh


10. Prepare the rootfs:

        cd Linux_for_Tegra/rootfs/
        sudo tar xpf ../../Tegra_Linux_Sample-Root-Filesystem_r36.4.3_aarch64.tbz2

        cd ..
        sudo ./tools/l4t_flash_prerequisites.sh
        sudo ./apply_binaries.sh
        sudo ./tools/l4t_create_default_user.sh -u user -p 123 -n nx1

11. Install kernel modules:

    In Linux_for_Tegra/source run:

        export INSTALL_MOD_PATH=../../Linux_for_Tegra/rootfs/
        ./nvbuild.sh -i

12. Get the Linux kernel image from:

        Linux_for_Tegra/source/kernel_out/kernel/kernel-jammy-src/arch/arm64/boot/Image


13. Build the QEMU rootfs image:

        qemu-img create -f raw rootfs_ubuntu_44gb.img.raw 44G
        mkfs.ext4 rootfs_ubuntu_44gb.img.raw
        sudo mount rootfs_ubuntu_44gb.img.raw /mnt
        sudo rsync -avxHAX --progress /data/Linux_for_Tegra/rootfs/ /mnt
        sudo umount /mnt/ext4/

# Run the Ubuntu image on Ghaf:

1. Make sure that the gpu-vm is enabled in [nvidia
   flake-module](../../../targets/nvidia-jetson-orin/flake-module.nix)

2. Edit [gpuvm.nix](../../../modules/microvm/virtualization/microvm/gpuvm.nix)
   and comment out the passthrough devices on the QEMU extraArgs:

    ```bash
        qemu = {

            # Devices to passthrough to the GPU-VM
            extraArgs = [
            "-dtb"
            "${gpuvm-dtb.out}/tegra234-gpuvm.dtb"
            # "-device"
            # "vfio-platform,host=60000000.vm_hs_p,mmio-base=0x60000000"
            # "-device"
            # "vfio-platform,host=80000000.vm_cma_p,mmio-base=0x80000000"
            # "-device"
            # "vfio-platform,host=100000000.vm_cma_vram_p,mmio-base=0x100000000"
            # "-device"
            # "vfio-platform,host=17000000.gpu"
            # "-device"
            # "vfio-platform,host=13e00000.host1x_pt"
            # "-device"
            # "vfio-platform,host=15340000.vic"
            # "-device"
            # "vfio-platform,host=15480000.nvdec"
            # "-device"
            # "vfio-platform,host=15540000.nvjpg"
            # "-device"
            # "vfio-platform,host=d800000.dce"
            # "-device"
            # "vfio-platform,host=13800000.display"
            ];
    ```

3. Rebuild Ghaf

4. Copy the Ubuntu Linux kernel image and rootfs to your NVIDIA Jetson device

5. On Ghaf, capture your gpu-vm launch command with:

        ps -ef | grep tegra234-gpuvm.dtb

    You will get an output like this:

        microvm@gpu-vm /nix/store/pi38jy5ay8q4crxnmlgffcmnfx0c4nh2-qemu-host-cpu-only-aarch64-unknown-linux-gnu-9.2.0/bin/qemu-system-aarch64 -name gpu-vm -M 'virt,accel=kvm:tcg,gic-version=max' -m 6000 -smp 4 -nodefaults -no-user-config -no-reboot -kernel /nix/store/gc4q5k8q37v09bm9w7gsky9wa3lw8k5i-linux-aarch64-unknown-linux-gnu-5.15.148/Image -initrd /nix/store/5xlnmpy1q71rymrcin5x0919r8px9jb3-initrd-linux-aarch64-unknown-linux-gnu-5.15.148/initrd -chardev 'stdio,id=stdio,signal=off' -device virtio-rng-pci -serial chardev:stdio -enable-kvm -cpu host -append 'console=ttyAMA0 reboot=t panic=-1 clk_ignore_unused pd_ignore_unused root=fstab loglevel=4 audit=1 init=/nix/store/2cp6ils6wviikp8y41q9znbxhj7hshw6-nixos-system-gpu-vm-25.05pre-git/init regInfo=/nix/store/3v7gzn2sj4l98i3bazgna7sc8l3is2pn-closure-info/registration' -nographic -sandbox on -qmp unix:gpu-vm.sock,server,nowait -drive 'id=vda,format=raw,file=/storagevm/homes/gpu-vm-home.img,if=none,aio=io_uring,discard=unmap,cache=none,read-only=off' -device 'virtio-blk-pci,drive=vda' -object 'memory-backend-memfd,id=mem,size=6000M,share=on' -numa 'node,memdev=mem' -chardev 'socket,id=fs0,path=gpu-vm-virtiofs-ro-store.sock' -device 'vhost-user-fs-pci,chardev=fs0,tag=ro-store' -chardev 'socket,id=fs1,path=gpu-vm-virtiofs-hostshare.sock' -device 'vhost-user-fs-pci,chardev=fs1,tag=hostshare' -netdev 'tap,id=tap-gpu-vm,ifname=tap-gpu-vm,script=no,downscript=no,queues=4' -device 'virtio-net-pci,netdev=tap-gpu-vm,mac=02:AD:00:00:00:03,romfile=,mq=on,vectors=10' -dtb /nix/store/zixbmmb5qphx5zpasqmq5n6wnz6mxnfw-gpuvm-dtb-aarch64-unknown-linux-gnu/tegra234-gpuvm.dtb

    Get from that output the device tree derivation output:

        /nix/store/zixbmmb5qphx5zpasqmq5n6wnz6mxnfw-gpuvm-dtb-aarch64-unknown-linux-gnu/tegra234-gpuvm.dtb

    Stop the gpu-vm microvm:

        sudo systemctl stop microvm@gpu-vm.service

    Get the device tree from before and run the Ubuntu VM with:

        sudo qemu-kvm \
            -nographic \
            -machine virt,accel=kvm \
            -cpu host \
            -smp 4 \
            -m 4G \
            -no-reboot \
            -kernel ./Image \
            -drive file=rootfs_ubuntu_44gb.img.raw,if=virtio,format=raw \
            -net user,hostfwd=tcp::2222-:22 -net nic \
            -dtb /nix/store/zixbmmb5qphx5zpasqmq5n6wnz6mxnfw-gpuvm-dtb-aarch64-unknown-linux-gnu/tegra234-gpuvm.dtb \
            -device vfio-platform,host=60000000.vm_hs_p,mmio-base=0x60000000 \
            -device vfio-platform,host=80000000.vm_cma_p,mmio-base=0x80000000 \
            -device vfio-platform,host=100000000.vm_cma_vram_p,mmio-base=0x100000000 \
            -device vfio-platform,host=17000000.gpu \
            -device vfio-platform,host=13e00000.host1x_pt \
            -device vfio-platform,host=15340000.vic \
            -device vfio-platform,host=15480000.nvdec \
            -device vfio-platform,host=15540000.nvjpg \
            -device vfio-platform,host=d800000.dce \
            -device vfio-platform,host=13800000.display \
            -device qemu-xhci,id=usb \
            -device usb-host,bus=usb.0,vendorid=0x046d,productid=0xc52b \
            -device usb-host,bus=usb.0,vendorid=0x046d,productid=0x08e5 \
            -append "rootwait root=/dev/vda console=ttyAMA0 loglevel=7 debug clk_ignore_unused pd_ignore_unused"

    Replace the USB vendorid and productid of the connected mouse and keyboard
    to interact with the Ubuntu VM.


# Results:

To test if the VM is working with Ghaf:

1. Log to gpu-vm: `ssh gpu-vm`
2. Run ollama service: `sudo ollama serve`
3. In another gpu-vm terminal, run the deepseek-r1 model: `sudo ollama run
   deepseek-r1:1.5b`
4. Write a request, i.e. "What is a dog?"
5. Check GPU usage with the command `tegrastats`
  ```
  02-21-2025 16:28:22 RAM 364/6030MB (lfb 2x4MB) CPU [6%,1%,0%,0%] GR3D_FREQ 0%
  02-21-2025 16:28:23 RAM 364/6030MB (lfb 2x4MB) CPU [9%,0%,0%,0%] GR3D_FREQ 0%
  02-21-2025 16:28:24 RAM 364/6030MB (lfb 2x4MB) CPU [10%,14%,2%,3%] GR3D_FREQ 0%
  02-21-2025 16:28:25 RAM 376/6030MB (lfb 1x4MB) CPU [12%,51%,27%,11%] GR3D_FREQ 4%
  02-21-2025 16:28:26 RAM 485/6030MB (lfb 2x4MB) CPU [9%,17%,27%,47%] GR3D_FREQ 99%
  ```

If GR3D_FREQ that represents the GPU usage increases while you are using ollama,
this means that the model is using the GPU.

**NOTE:** When you run `sudo ollama serve` the expected output when the NVIDIA
GPU is detected is:

    [root@gpu-vm:/home/ghaf]# ollama serve
    Couldn't find '/root/.ollama/id_ed25519'. Generating new private key.
    Your new public key is:

    ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIEc1aHCShO7oc4y8kAt/0lPASWX7FiAZ0rHJhGJIw+MY

    2025/02/27 21:01:41 routes.go:1186: INFO server config env="map[CUDA_VISIBLE_DEVICES: GPU_DEVICE_ORDINAL: HIP_VISIBLE_DEVICES: HSA_OVERRIDE_GFX_VERSION: HTTPS_PROXY: HTTP_PROXY: NO_PROXY: OLLAMA_DEBUG:false OLLAMA_FLASH_ATTENTION:false OLLAMA_GPU_OVERHEAD:0 OLLAMA_HOST:http://127.0.0.1:11434 OLLAMA_INTEL_GPU:false OLLAMA_KEEP_ALIVE:5m0s OLLAMA_KV_CACHE_TYPE: OLLAMA_LLM_LIBRARY: OLLAMA_LOAD_TIMEOUT:5m0s OLLAMA_MAX_LOADED_MODELS:0 OLLAMA_MAX_QUEUE:512 OLLAMA_MODELS:/root/.ollama/models OLLAMA_MULTIUSER_CACHE:false OLLAMA_NOHISTORY:false OLLAMA_NOPRUNE:false OLLAMA_NUM_PARALLEL:0 OLLAMA_ORIGINS:[http://localhost https://localhost http://localhost:* https://localhost:* http://127.0.0.1 https://127.0.0.1 http://127.0.0.1:* https://127.0.0.1:* http://0.0.0.0 https://0.0.0.0 http://0.0.0.0:* https://0.0.0.0:* app://* file://* tauri://* vscode-webview://*] OLLAMA_SCHED_SPREAD:false ROCR_VISIBLE_DEVICES: http_proxy: https_proxy: no_proxy:]"
    time=2025-02-27T21:01:41.131Z level=INFO source=images.go:432 msg="total blobs: 0"
    time=2025-02-27T21:01:41.132Z level=INFO source=images.go:439 msg="total unused blobs removed: 0"
    time=2025-02-27T21:01:41.135Z level=INFO source=routes.go:1237 msg="Listening on 127.0.0.1:11434 (version 0.5.11)"
    time=2025-02-27T21:01:41.145Z level=INFO source=gpu.go:217 msg="looking for compatible GPUs"
    NvTegraPrivGetProductionMode: Could not read Tegra production mode
    Expected on kernels without fuse support
    time=2025-02-27T21:01:42.643Z level=INFO source=types.go:130 msg="inference compute" id=GPU-de035b67-6e28-5ed3-93e9-a13461f2c540 library=cuda variant=v12 compute=8.7 driver=12.6 name=Orin total="4.0 GiB" available="3.9 GiB"

The following line indicates that the NVIDIA GPU is available with 3.9GB of
memory:

    id=GPU-de035b67-6e28-5ed3-93e9-a13461f2c540 library=cuda variant=v12 compute=8.7 driver=12.6 name=Orin total="4.0 GiB" available="3.9 GiB"

The next is an expected error, because we are not passing through the fuse
device:

    NvTegraPrivGetProductionMode: Could not read Tegra production mode
    Expected on kernels without fuse support

You must see this error when implementing the display passthrough with wayland.

# List of TODOs

1. Display passthrough is working with Ubuntu VM but not with microvm GPU-VM.
   Probably some driver modifications are needed in the nvidia-drm module. I
   suggest running the Ubuntu VM, checking that the display is working with X11,
   and then moving Ubuntu to wayland to confirm if there is a driver problem or
   a microvm package, library, or module missing.

2. There are various hardcoded configurations in the passthrough drivers. Some
   virtualization functions are needed (similar to BPMP) for this. The devices
   that need to be virtualized are:
   - fuse@3810000: check hardcoded info in
     [0001-gpu-add-support-for-passthrough.patch](../../../modules/microvm/virtualization/microvm/gpuvm_res/0001-gpu-add-support-for-passthrough.patch),
     line 84
   - chip id: check hardcoded in patch:
     [0001-tegra-fixed-chip-id.patch](../../../modules/microvm/virtualization/microvm/gpuvm_res/0001-tegra-fixed-chip-id.patch)
   - memory-controller@2c00000: check hardcoded in patch:
     [0002-Add-support-for-gpu-display-passthrough.patch](modules/microvm/virtualization/microvm/gpuvm_res/0002-Add-support-for-gpu-display-passthrough.patch)
     line 105


# Hardware accelerators passthrough status

The hardware accelerators passthrough was a work in progress. This is a brief
status about GPU and hardware accelerators passthrough. Inside the NVIDIA
Multimedia Complex, there is a Host Controller (host1x) that is the interface
between the SoC controllers (GPU, encoders, video image compositors, cameras,
etc.).

In Q3-2023, we made the host1x passthrough to GPU-VM to enable the GPU
passthrough. The LLM demo worked okay because only the GPU accelerator was used,
and no communication with other hardware blocks was needed.

For drones solita use case, the GPU and the hardware accelerators blocks are
used in the docker container. Here, these blocks have tasks that require
synchronization between them at driver level. For instance, a video frame is
preprocessed by the VIC (video image compositor) and then passed to the GPU.

We were able to passthrough the host1x, GPU, and hardware accelerators to the
GPU-VM, but we found that it fails when the VIC (video image compositor) waits
for a host1x synchronization point, because the host1x driver is not able to
read the VIC status IO registers.

We were able to replicate the mentioned problem in the host by removing elements
in the device tree. We found that the IOMMU is needed by the host1x driver in
the host in order for it to access other devices' IO registers. **THE PROBLEM:**
we are not passing through the IOMMU to the VM.


## Possible solutions to the IOMMU PROBLEM:

- Use nested IOMMU. The good news is that Nvidia Orin has SMMUv2 which in theory
  supports nested address translations, and QEMU has recently added support for
  it.

- Modify host1x driver so that the access to the device IO registers will be
  done without IOMMU mapping, at kernel level. This will not be a security
  problem because the host1x will be in the GPU-VM and the VM access is already
  restricted by the IOMMU.

- Keep the host1x in the host (same implementation that Nvidia is doing with its
  hypervisor), and adapt the host1x virtualization services to work with
  Qemu/KVM.
