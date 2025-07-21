# Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  imports = [
    ./apparmor
    ./audit
    ./disk-encryption.nix
    ./fail2ban.nix
    ./pwquality.nix
    ./ssh-tarpit
  ];
}
