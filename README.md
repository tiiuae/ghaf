# Spectrum OS custom configuration layer

## Status

Work in progress to adapt device specific and customer-specific out-of-tree configurations for Spectrum OS.

## Building customized Spectrum OS image

#### Create build directory and clone all components there:

    # Upstream Spectrum OS sources:
    $ git clone -b wayland https://spectrum-os.org/git/spectrum
    $ git clone -b wayland https://spectrum-os.org/git/nixpkgs-spectrum

    # This repo:
    $ git clone https://github.com/tiiuae/<this-repo-name>

#### Build image using specific configuration:
While in build directory, run

    $ nix-build -I nixpkgs=nixpkgs-spectrum -I spectrum-config=<this-repo-name>/<config-name>.nix <this-repo-name>/release/live/

You can add `nixpkgs` and `spectrum-config` variables to your `NIX_PATH`

#### Flash and run image:
The successful build produces `result` link in build directory. Run
```
$ sudo dd if=result of=/dev/<SDcard> bs=1M conv=fsync status=progress oflag=direct
```
to flash the image to your SD card.
```
Hint: you can find which /dev/ file is your SDcard using 'lsblk' and 'dmesg' commands.
```
Put SD card into the board and switch it on. You should see a lovely Spectrum desktop  at your display.

## Temporary limitations and known issues

1. Currently the only device supported is `imx8qm-evk`, more devices very soon!
2. There is no cross-compilation support (yet). Use native `aarch64` hardware to build the image.
3. There are still some hardware-specific parts that need to be reworked.

## More info

See https://spectrum-os.org/doc/development/build-configuration.html
