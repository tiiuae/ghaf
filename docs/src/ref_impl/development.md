<!--
    Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
    SPDX-License-Identifier: CC-BY-SA-4.0
-->

# Development

Ghaf Framework is free software, currently under active development.

The scope of target support is updated with development progress:

* [Build and Run](./build_and_run.md)
* [Running Remote Build on NixOS](./remote_build_setup.md)
* [Installer](./installer.md)
* [Cross-Compilation](./cross_compilation.md)
* [Creating Application VM](./creating_appvm.md)
* [labwc Desktop Environment](./labwc.md)
* [idsvm Further Development](./idsvm-development.md)
* [systemd Service Hardening](./systemd-service-config.md)

Once you are up and running, you can participate in the collaborative development process by building a development build with additional options. For example, with the development username and password that are defined in [accounts.nix](https://github.com/tiiuae/ghaf/blob/main/modules/common/users/accounts.nix).

If you authorize your development SSH keys in the [ssh.nix](https://github.com/tiiuae/ghaf/blob/main/modules/common/development/authorized_ssh_keys.nix#L4-L21) module and rebuild Ghaf for your target device, you can use `nixos-rebuild switch` to quickly deploy your configuration changes to the target device over the network using SSH. For example:

    nixos-rebuild --flake .#nvidia-jetson-orin-agx-debug --target-host root@<ip_address_of_ghaf-host> --fast switch
    ...
    nixos-rebuild --flake .#lenovo-x1-carbon-gen11-debug --target-host root@<ip_address_of_ghaf-host> --fast switch
    ...

> With the `-debug` targets, the debug ethernet is enabled on host. With Lenovo X1 Carbon, you can connect USB-Ethernet adapter for the debug and development access.

Pull requests are the way for contributors to submit code to the Ghaf project. For more information, see [Contribution Guidelines](../appendices/contributing_general.md).
