<!--
    Copyright 2022-2023 TII (SSRC) and the Ghaf contributors
    SPDX-License-Identifier: CC-BY-SA-4.0
-->

# Cross-Compilation

> Cross-compilation is currently under development and cannot be used properly on the supported devices.

Ghaf is targeted at a range of devices and form factors that support different instruction set architectures (ISA). Many small form-factor edge devices are not powerful enough to compile the needed applications or OSs that run on them. As the most common ISA used in desktops and servers is ``x_86``, this will generally require that the code is cross-compiled for target ISA e.g. ``AArch64`` or ``RISC-V``.

NixOS and Nixpkgs have good support for cross-compilation, however, there are still some that can not be compiled in this way.


## binfmt

[binfmt](https://en.wikipedia.org/wiki/Binfmt_misc) allows running different ISA on a development machine. This is achieved by running the target binary in an emulator such as ``QEMU`` or in a VM.

To enable ``binfmt``, we recommend to set the following in your host systems ``configuration.nix``:

    boot.binfmt.emulatedSystems = [
      "riscv64-linux"
      "aarch64-linux"
    ];

In addition, it is recommended to enable KVM support with either

    boot.kernelModules = [ "kvm-amd" ];

or

    boot.kernelModules = [ "kvm-intel" ];

depending on whether your development host is running AMD or Intel processor.

## Cross Compilation for Microchip Icicle Kit (RISCV64)
SD Image for Microchip Icicle kit can be cross compiled from x86 machine. To generate the release/debug SD Image run following command:

```
 $> nix build .#packages.riscv64-linux.mpfs-icicle-kit-<release/debug>
```

## Future Cross-Compilation Support

This will involve working with upstream package maintainers to ensure that the packages are cross-compilation aware. This will be addressed on a package-by-package basis.

