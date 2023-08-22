<!--
    Copyright 2022-2023 TII (SSRC) and the Ghaf contributors
    SPDX-License-Identifier: CC-BY-SA-4.0
-->

# Development

Ghaf Framework is free software, currently under active development.

Scope of target support is updated with development progress.

Once you are up and running, you can participate in the collaborative development process by building a development build with additional options. For example, with the development username and password that are defined in the [authentication.nix](https://github.com/tiiuae/ghaf/blob/main/modules/development/authentication.nix#L4-L5) module.

If you set up development SSH keys in the [ssh.nix](https://github.com/tiiuae/ghaf/blob/main/modules/development/ssh.nix#L4) module, you can use `nixos-rebuild switch` to quickly deploy your configuration changes to the development board over the network using SSH:

    nixos-rebuild --flake .#packages.aarch64-linux.nvidia-jetson-orin-agx-debug --target-host root@ghaf-host --fast switch



Pull requests are the way for contributors to submit code to the Ghaf project. For more information, see [Contribution Guidelines](../appendices/contributing_general.md).
