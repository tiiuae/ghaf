<!--
    Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
    SPDX-License-Identifier: CC-BY-SA-4.0
-->

# Hardening

This section describes how securing Ghaf by reducing its attack surface—hardening—is done.


## Kernel

Ghaf has two types of kernels: host and guest. Hardening of these kernels varies in terms of hardware support and functionality required by the guest kernel in question. Within this context, the kernel always refers to the Linux operating system kernel.


### Kernel Hardening Process

NixOS provides several mechanisms to customize the kernel. The main methods are:

* [Declaring kernel command line parameters](https://nixos.wiki/wiki/Linux_kernel#Custom_kernel_commandline): [usage in Ghaf](https://github.com/search?q=repo%3Atiiuae%2Fghaf%20kernelparams&type=code).
* [Declaring kernel custom configuration](https://nixos.org/manual/nixos/stable/#sec-linux-config-customizing): [usage in Ghaf](https://github.com/tiiuae/ghaf/blob/main/modules/host/kernel.nix).
    
    Example of entering the kernel development shell to customize the `.config` and build it:

  ```
  ~/ghaf $ nix develop .#devShells.x86_64-linux.kernel-x86
  ...
  [ghaf-kernel-devshell:~/ghaf/linux-6.6.2]$ cp ../modules/host/ghaf_host_hardened_baseline .config
  [ghaf-kernel-devshell:~/ghaf/linux-6.6.2]$ make menuconfig
  ...
  [ghaf-kernel-devshell:~/ghaf/linux-6.6.2]$ make -j$(nproc)
  ...
  Kernel: arch/x86/boot/bzImage
  ```

* Booting the built kernel with QEMU:

  ```
  [ghaf-kernel-devshell:~/ghaf/linux-6.6.2]$ qemu-system-x86_64 -kernel arch/x86/boot/bzImage
  ```

* [Validating with kernel hardening checker](https://github.com/a13xp0p0v/kernel-hardening-checker):

  ```
  [ghaf-kernel-devshell:~/ghaf/linux-6.6.2]$ kernel-hardening-checker -c ../modules/host/ghaf_host_hardened_baseline
  [+] Kconfig file to check: ../modules/host/ghaf_host_hardened_baseline
  [+] Detected microarchitecture: X86_64
  [+] Detected kernel version: 6.6
  [+] Detected compiler: GCC 120200
  ...
  [+] Config check is finished: 'OK' - 103 / 'FAIL' - 84
  ```


### Host Kernel

The host kernel runs on bare metal. The kernel is provided either with Linux upstream (`x86_64`) or with vendor BSP. The default Ghaf host kernel on `x86_64` is maintained by Ghaf upstream package sources `nixpkgs` or Nix-packaged hardware-specific BSP (for example, NVIDIA Jetson-family of devices).


#### `x86-64-linux`

The host kernel hardening is based on Linux `make tinyconfig`. The default `tinyconfig` fails to assertions on NixOS without modifications. Assertions are fixed in `ghaf_host_hardened_baseline` Linux configuration under Ghaf `modules/host/`.

In addition, NixOS (Ghaf baseline dependency) requires several kernel modules that are added to the config or ignored with `allowMissing = true`. As of now, the kernel builds and early boots on Lenovo X1.
