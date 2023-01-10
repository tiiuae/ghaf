# TII SSRC Secure Technologies: Ghaf Framework

This repository contains the source code of Ghaf Framework — an open-source project for enhancing security through compartmentalization on edge devices.

Other repositories that are a part of the Ghaf project:

* https://github.com/tiiuae/sbomnix


## Build Instructions

Ghaf utilizes a flake only approach to build the framework. To see provided outputs, type `nix flake show`.


### x86-64

To build the VM-image for x86-64, use:

    nix build .#packages.x86_64-linux.vm

Run the above x86-64 VM-image inside QEMU:

    nix run .#packages.x86_64-linux.vm

or

    result/bin/run-ghaf-host-vm


The development username and password are defined in [authentication module](./modules/development/authentication.nix).

> **NOTE:** this creates `ghaf-host.qcow2` copy-on-write overlay disk image in your current directory. If you do unclean shutdown for the QEMU VM, you might get weird errors the next time you boot. Simply removing `ghaf-host.qcow2` should be enough. To cleanly shut down the VM, from the menu bar of the QEMU Window, click Machine and then click Power Down.


### NVIDIA Jetson Orin (AArch64)

To build for the NVIDIA Jetson Orin, use:

    nix build .#packages.aarch64-linux.nvidia-jetson-orin

Flash the resulting `image eg.` to an SD card or USB drive:

    dd if=./result/nixos.img of=/dev/<YOUR_USB_DRIVE> bs=32M


### Cross Compilation Complications

As there are some packages that are not cross-compilation aware, set the following in your `configuration.nix` to enable binfmt:

    {
      boot.binfmt.emulatedSystems = [
        "riscv64-linux"
        "aarch64-linux"
      ];
    }

For more details, see [Cross Compilation](https://tiiuae.github.io/ghaf/build_config/cross_compilation.html).


### Documentation

This is a source repository for https://tiiuae.github.io/ghaf. 

To build the Ghaf documentation, use:

    nix build .#doc
    
  
See the documentation overview under [docs](./docs/README.md).


## Contributing

We welcome your contributions to code and documentation.

If you would like to contribute, please read [CONTRIBUTING.md](CONTRIBUTING.md) and consider opening a pull request. One or more maintainers will use GitHub's review feature to review your pull request.

If you find any bugs or errors in the content, feel free just to create an [issue](https://github.com/tiiuae/ghaf/issues). You can also use this feature to track suggestions or other information.


## License

Ghaf is made available under the Apache License, Version 2.0. See [LICENSE](./LICENSE) for the full license text.
