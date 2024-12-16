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
    ./users
    ./version
    ./virtualization/docker.nix
    ./systemd
    ./services
    ./networking
    #TODO: this should be moved to where it is needed and included on demand
    # if it is a common then the file should be moved to common
    ../hardware/definition.nix
    ./logging
  ];
}
