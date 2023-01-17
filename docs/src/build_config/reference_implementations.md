# Reference Implementations

## Supported targets

| Hardware         | Architecture     | Scope         |
|---               |---               |---            |
| Generic Intel    | x86              | QEMU          |
| NVIDIA Orin AGX  | aarch64          | hardware      |

Scope of target support is updated with development progress.

## Build Instructions

Ghaf uses a Nix flake only approach to build the framework targets.

See [Nix installation instructions](https://nixos.org/download.html) for further details.
Make also sure to [enable flakes](https://nixos.wiki/wiki/Flakes#Enable_flakes).

| Hardware         | architecture     | scope | build command                                           |
|---               |---               |---    |---                                                      |
| Generic Intel    | x86              | VM    | `nix build .#packages.x86_64-linux.vm`                  |
| NVIDIA Orin AGX  | aarch64          | HW    | `nix build .#packages.aarch64-linux.nvidia-jetson-orin` |

To see all Ghaf supported outputs, type `nix flake show`.

## Run Instructions

The development username and password are defined in [authentication module](https://github.com/tiiuae/ghaf/blob/main/modules/development/authentication.nix#L4-L5).

### Virtual machine - ghaf-host

`nix run .#packages.x86_64-linux.vm`

> **NOTE:** this creates `ghaf-host.qcow2` copy-on-write overlay disk image in your current directory. If you do unclean shutdown for the QEMU VM, you might get weird errors the next time you boot. Simply removing `ghaf-host.qcow2` should be enough. To cleanly shut down the VM, from the menu bar of the QEMU Window, click Machine and then click Power Down.

### NVIDIA Jetson Orin AGX

* Prequisite (firmware version): [Update the NVIDIA Jetson Orin AGX UEFI firmware to version r35.1 to boot from USB](https://github.com/mikatammi/jetpack-nixos/tree/flash_orin_hack#hack-for-flashing-nvidia-jetson-orin)
* Prequisite (cross-compilation support): `binfmt` and NixOS is required.
  * Enable `binfmt` in your `configuration.nix` with:
    ```
    boot.binfmt.emulatedSystems = [
      "aarch64-linux"
    ];
    ```
  * For more details, see [Cross Compilation](https://tiiuae.github.io/ghaf/build_config/cross_compilation.html).
* Prepare the USB boot media with the target HW image you built:
  * `dd if=./result/nixos.img of=/dev/<YOUR_USB_DRIVE> bs=32M`
* Boot the hardware from USB media


## Development tips

If you set up development SSH keys into [SSH module](https://github.com/tiiuae/ghaf/blob/main/modules/development/ssh.nix#L4), you can use `nixos-rebuild switch` to quickly deploy your configuration changes to the development board over the network using SSH:

    nixos-rebuild --flake .#nvidia-jetson-orin --target-host root@orin-hostname --fast switch
