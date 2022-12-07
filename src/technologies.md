# Technologies

## Overview

Embedded virtualization builds on technologies from cloud security. Cloud services provide scalable but isolated computation - your business case is isolated from someone else's business case. At hardware level. Similarly, hardware support in modern personal devices has enabled isolation of device resources with virtualization. This provides the baseline for secure system design for use case protection. In practice, user can use the same device with a trusted application and with an untrusted application. Both application isolated from each other to protect valuable user data and privacy. Our systems are built using [nixpkgs](https://github.com/NixOS/nixpkgs) and [Spectrum OS](https://spectrum-os.org/) build configurations.

## Hardware Requirements for Virtualization

Protected computation resources include: CPU, memory, storage and other IO devices. Allocation of these resources is managed with hypervisor. In our reference implementation, we use KVM (Kernel Virtual Machine) from Linux to virtualize hardware access. From hardware, this requires MMU (memory management unit) for CPU physical to virtual address mapping and IOMMU for direct memory access (DMA) capable device virtual addresses to physical addresses of the main memory. Many 64-bit CPUs support virtualization via hypervisor extensions already. Our reference implementation supports x86_64 and aarch64 and we follow RISC-V hypervisor extensions development.

Our current reference hardware is [NXP iMX8 QM development board](https://github.com/tiiuae/spectrum-config-imx8). In addition, x86_64 hardware is supported via Spectrum OS upstream.

## Virtual Machine Manager (VMM)

On top of operating system (OS) kernel hypervisor support with KVM - we allocate virtual resources for use cases with user space virtual machine manager (VMM) using [rust-vmm](https://github.com/rust-vmm) and [cloud-hypervisor](https://github.com/cloud-hypervisor/cloud-hypervisor). Other VMMs, [crosvm](https://github.com/google/crosvm) and [QEMU](https://www.qemu.org/), are used in development. In addition, we have also experimental, aarch64 demonstrated support for a KVM variant - [KVMS](https://github.com/jkrh/kvms) which adds security features to standard KVM.

