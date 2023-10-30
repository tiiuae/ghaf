<!--
    Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
    SPDX-License-Identifier: CC-BY-SA-4.0
-->

# Installer

Ghaf has a NixOS-like non-interactive, declarative installer instead of a
conventional (imperative, non-declarative) installer as in most conventional
Linux distributions. This is possible with the [Ghaf as
Library](https://github.com/tiiuae/ghaf/pull/ghaf-based-project.md) approach:
rather than clicking similar options during installation, you can configure the
system once and deploy this configuration to the desired machines.


To implement the pre-configured setting up approach, we used the
[nixos-anywhere](https://github.com/nix-community/nixos-anywhere) tool.

There are two separate ways to use it:
* manually
* with the Ghaf installation wizard.
> NOTE: The Ghaf installation wizard is currently under development and cannot be used to create the required system configuration.

## Manual Installation

To install Ghaf manually:

1. Create your own flake using the Ghaf template:

```sh
nix flake init -t github:tiiuae/ghaf#target-x86_64-generic
```

2. Edit it according to your preferences.

3. Set the value of `ghaf.installer.sshKeys` to get an installer image. If you don't have ssh keys follow substeps:

    3.1. Generate an SSH keypair as follows:
         ```
         $ ssh-keygen -t ed25519
         Generating public/private ed25519 key pair.
         Enter file in which to save the key (/home/user/.ssh/id_ed25519): /home/user/.ssh/id_ed25519_installer
         Enter passphrase (empty for no passphrase):
         Enter same passphrase again:
         Your identification has been saved in /home/user/.ssh/id_ed25519_installer
         Your public key has been saved in /home/user/.ssh/id_ed25519_installer.pub
         ...
         ```

    3.2. Copy public key from file (`id_ed25519_installer.pub` in an example above) in place of stub in `flake.nix` of your configuration.

4. Build the installer image:

```sh
nix build .#nixosConfigurations.PROJ_NAME-ghaf-debug.config.system.build.installer
```

5. Flash the installer image to your device (temporary storage which will be used to establish connection with the host machine):

```sh
sudo dd if=./result/iso/nixos-...-linux.iso of=/dev/YOUR_DEVICE conv=sync && sync
```

6. Run the image on the device.

7. Connect the device to the network using `wifi-connector`.

8. Check the target block device name using the lsblk command and put it in the disk configuration option in `flake.nix`.

8. Install the NixOS configuration to the target device using the command:

```sh
nix run github:nix-community/nixos-anywhere -- --flake .#CONFIGURATION_NAME root@IP_ADDRESS
```
