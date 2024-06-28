# Copyright 2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# Common ghaf modules
#
{
  imports = [
    ./boot/systemd-boot-dtb.nix
    ./common.nix
    ./development
    ./firewall
    ./profiles
    ./security
    ./users/accounts.nix
    ./version
    ./virtualization/docker.nix
    ./systemd
    ./services
    ./networking
    ../hardware/definition.nix
    ./log
  ];
}
