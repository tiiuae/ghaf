# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# Firewall related modules
#
{
  _file = ./default.nix;

  imports = [
    ./kernel-modules.nix
    ./firewall.nix
    ./attack-mitigation.nix
  ];
}
