# Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  imports = [
    ./sshkeys.nix
    ./apparmor
    ./clamav
    ./fail2ban
    ./firejail
    ./networking.nix
    ./system.nix
  ];
}
