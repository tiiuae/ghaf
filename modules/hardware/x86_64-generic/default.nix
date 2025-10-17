# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  imports = [
    # Kernel components are exposed at the upper level as modules
    ./x86_64-linux.nix
    ./modules/tpm2.nix
  ];
}
