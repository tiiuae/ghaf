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
    ./hardware
    ./profiles
    ./security
    ./tpm2
    ./users/accounts.nix
    ./version
    ./virtualization/docker.nix
    ./systemd
    ./networking
  ];
}
