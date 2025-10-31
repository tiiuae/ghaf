# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  imports = [
    ./disk-encryption.nix
    ./sshkeys.nix
    ./apparmor
    ./audit
    ./pwquality.nix
    ./fail2ban.nix
    ./ssh-tarpit
    ./clamav.nix
  ];
}
