The following are sample commands to illustrate the process of signing the Ghaf installer ISO for Secure Boot.

The idea is to progressively unpack the layers of the CD iso until we reach the raw NixOS disk image. At this point we
can sign it with the `sign_disk_image.sh` script and recreate the installer by doing the steps in reverse.

```shell
# This contains a patch to output the make-iso-image pathlist in the derivation
nix build .#lenovo-x1-carbon-gen11-debug-installer
cd ..
mkdir temp
cd temp
nix run ../ghaf#sign-installer ../ghaf/result/
```