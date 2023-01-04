# Cross Compilation

Ghaf is targeted at a range of devices and form factors that support different Instruction Set Architectures (ISA). Many small form-factor edge devices are not powerful enough to compile the needed applications or operating systems that run on them. As the most common ISA used in desktops and servers is ``x\_86``, this will generally require that the code is cross-compiled for target ISA e.g. ``AArch64`` or ``RISC-V``.

NixOS and Nixpkgs have good support for cross-compilation, however, there are still some that can not be compiled in this way.

## Binfmt

[binfmt](https://en.wikipedia.org/wiki/Binfmt_misc) allows running different ISA on a development machine. This is achieved by running the target binary in an emulator such as ``QEMU`` or in a virtual machine.

To enable binfmt, it is advisable to set the following in your host systems ``configuration.nix``:

    boot.binfmt.emulatedSystems = [
      "riscv64-linux"
      "aarch64-linux"
    ];
    
In addition it is recommended to enable KVM support with either:

    boot.kernelModules = [ "kvm-amd" ];

or

    boot.kernelModules = [ "kvm-intel" ];
    
depending on whether your development host is running ``AMD`` or ``Intel`` version of ``x\_86``.

## Future Cross Compilation Support

This will involve working with upstream package maintainers to ensure that the packages are cross compilation aware. This will be addressed on a package-by-package basis.
    
