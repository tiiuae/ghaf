# Copyright 2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  imports = [
    ./kernel/guest
    ./kernel/hardening.nix
    ./kernel/host
    ./kernel/host/pkvm
    ./x86_64-linux.nix
  ];
}
