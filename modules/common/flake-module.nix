# Copyright 2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# Common ghaf modules
#
{
  flake.nixosModules = {
    common.imports = [
      ./common.nix
      ./firewall
      ./profiles
      ./security
      ./users
      ./version
      ./virtualization
      ./systemd
      ./services
      ./networking
      ./logging
    ];
  };
}
