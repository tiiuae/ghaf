# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  _file = ./default.nix;

  imports = [
    ./apparmor
    ./audit
    ./disk-encryption.nix
    ./fail2ban.nix
    ./pwquality.nix
    ./ssh-tarpit
    ./fleet
    ../../secureboot/secureboot.nix
  ];
}
