# Documentation for TII SSRC Secure Technologies: Ghaf Framework

The Ghaf project is an open-source framework for enhancing security through compartmentalization on edge devices. The source code that we use is in the following repositories:

* https://github.com/tiiuae/ghaf
* https://github.com/tiiuae/sbomnix


## Build Instructions


### x86\_64

To build the VM-image for x86\_64

    nix build .#packages.x86_64-linux.vm

To run the above x86\_64 VM-image inside QEMU:

    nix run .#packages.x86_64-linux.vm

or

    result/bin/run-nixos-vm


The development username and password are defined in [authentication module](./modules/development/authentication.nix).

Note: this creates nixos.qcow2 copy-on-write overlay disk image in your current directory. If you do unclean shutdown for the QEMU Virtual Machine, you might get weird errors the next time you boot. Simply removing the nixos.qcow2 should be enough. To cleanly shut down the VM, from the menu bar of the QEMU Window, click Machine and then click Power Down.


### NVIDIA Jetson Orin (aarch64)

To build for the NVIDIA Jetson Orin

    nix build .#packages.aarch64-linux.nvidia-jetson-orin

then flash the resulting image eg. to a SD card or USB drive

    dd if=./result/nixos.img of=/dev/<YOUR_USB_DRIVE> bs=32M


### Documentation

To build the documentation

    nix build .#doc
    

See the documentation overview under [docs](./docs/README.md)


## Contributing

If you would like to contribute, please read [Contributing](CONTRIBUTING.md) and consider opening a pull request. 

Some things that will increase the chance that your pull request is accepted faster:
* Spelling tools usage.
* Following our Style Guide.
* Writing a good commit message.

In addition, you can use [issues](https://github.com/tiiuae/ghaf/issues) to track suggestions, bugs, and other information.


## License

Ghaf is made available under the Apache License, Version 2.0. See [LICENSE](./LICENSE) for the full license text.
