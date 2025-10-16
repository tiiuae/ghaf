# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  imports = [
    ./kernel/guest
    ./kernel/hardening.nix
    ./kernel/host
    ./kernel/host/pkvm
    ./x86_64-linux.nix
    ./modules/tpm2.nix
  ];
}
