<!--
    Copyright 2022-2023 TII (SSRC) and the Ghaf contributors
    SPDX-License-Identifier: CC-BY-SA-4.0
-->

# Hardening

This section describes how securing Ghaf by reducing its' attack surface, in short - hardening, is done.

## Kernel

Ghaf has two types of kernels - host and guest kernels. Hardening of these kernels varies in terms of hardware support and functionality required by the guest kernel in question. Within this context, kernel always refers to Linux operating system kernel.

### Process of Kernel Hardening

NixOS provides several mechanisms to customize kernel. The main methods are:

* [declaring kernel command line parameters](https://nixos.wiki/wiki/Linux_kernel#Custom_kernel_commandline)
  * [Usage in Ghaf](https://github.com/search?q=repo%3Atiiuae%2Fghaf%20kernelparams&type=code)
* [declaring kernel custom configuration](https://nixos.org/manual/nixos/stable/#sec-linux-config-customizing)
  * [Usage in Ghaf](https://github.com/tiiuae/ghaf/blob/main/modules/host/kernel.nix)
  * Example of entering the kernel menuconfig to customize the `.config`:
  ```
  ❯ nix-shell '<nixpkgs>' -p pkgs.ncurses pkgs.pkg-config
  these 4 paths will be fetched (0.66 MiB download, 1.66 MiB unpacked):
  ...

  ~ via ❄️  impure (shell)
  ❯ nix-shell '<nixpkgs>' -A pkgs.linux_latest.configfile

  ~ via ❄️  impure (shell)
  ❯ unpackPhase

  ~ via ❄️  impure (linux-config-6.5.7)
  ❯ cd linux-6.5.7/

  ~/linux-6.5.7 via ❄️  impure (linux-config-6.5.7)
  ❯ make menuconfig
* Enter the kernel build environment
  ```
  nix-shell -E 'with import <nixpkgs> {}; linux.overrideAttrs (o: {nativeBuildInputs=o.nativeBuildInputs ++ [ pkg-config ncurses ];})'
  make -j16
  ...
  Kernel: arch/x86/boot/bzImage
  ```
* Boot the built kernel with QEMU
  ```
  qemu-system-x86_64 -kernel arch/x86/boot/bzImage
  ```
* [validating with kernel hardening checker](https://github.com/a13xp0p0v/kernel-hardening-checker)

### Host kernel

The host kernel runs on bare metal. The kernel is provided either via Linux upstream (`x86_64`) or via vendor board support package (BSP). The default Ghaf host kernel on `x86_64` is maintained by Ghaf upstream package sources - `nixpkgs` or nix-packaged hardware-specific BSP (e.g. NVIDIA Jetson-family of devices).

#### `x86-64-linux`

The host kernel hardening is based on Linux `make tinyconfig`. The default `tinyconfig` fails to assertions on NixOS without
modifications. Assertions are fixed in `ghaf_host_hardened_baseline` linux config under Ghaf `modules/host/`.
In addition, NixOS (Ghaf baseline dependency) requires several kernel modules that are added to the config or ignored with `allowMissing = true`;
As of now, the kernel builds and early boots on Lenovo X1.
