<!--
    Copyright 2022-2023 TII (SSRC) and the Ghaf contributors
    SPDX-License-Identifier: CC-BY-SA-4.0
-->

# Technologies

Embedded virtualization builds on technologies from cloud security. Cloud services provide scalable but isolated computation — your business case is isolated from someone else's business case.

At the hardware level. Similarly, hardware support in modern personal devices has enabled the isolation of device resources with virtualization. This provides the baseline for secure system design for use case protection.

In practice, the user can use the same device with a trusted application and with an untrusted application. Both applications are isolated from each other to protect valuable user data and privacy.

Our systems are built using [Nixpkgs](https://github.com/NixOS/nixpkgs) and various [Nix](https://nixos.org/guides/nix-language.html)-based tools and configurations. For more information on Nix ecosystem, see [nix.dev](https://nix.dev/).


## Hardware Requirements for Virtualization

Protected computation resources include CPU, memory, storage, and other IO devices. Allocation of these resources is managed with the hypervisor.

In our reference implementation, we use KVM (Kernel Virtual Machine) from Linux to virtualize hardware access. From hardware, this requires MMU (memory management unit) for CPU physical to virtual address mapping and IOMMU for direct memory access (DMA) capable device virtual addresses to physical addresses of the main memory. Many 64-bit CPUs support virtualization via hypervisor extensions already. Our reference implementation supports x86-64 and Aarch64, and we follow RISC-V hypervisor extensions development.


## Virtual Machine Manager (VMM)

On top of OS kernel hypervisor support with KVM. We allocate virtual resources for use cases with user-space virtual machine manager (VMM) using [rust-vmm](https://github.com/rust-vmm) based projects such as [cloud-hypervisor](https://github.com/cloud-hypervisor/cloud-hypervisor) and [crosvm](https://github.com/google/crosvm). [QEMU](https://www.qemu.org/) is enabled for certain development use cases.

In addition, we have also experimental, Aarch64 demonstrated support for a KVM variant — [KVMS](https://github.com/jkrh/kvms) — which adds security features to standard KVM.


## In This Chapter

- [Compartmentalization](./compartment.md)
- [Passthrough](./passthrough.md)
  - [Binding Device to VFIO Driver](./vfio.md)
  - [NVIDIA Jetson AGX Orin: UART Passthrough](./nvidia_agx_pt_uart.md)
  - [NVIDIA Jetson AGX Orin: PCIe Passthrough](./nvidia_agx_pt_pcie.md)
  - [Generic x86: PCIe Passthrough on crosvm](./x86_pcie_crosvm.md)
- [Hypervisor Options](./hypervisor_options.md)
