# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  _file = ./default.nix;

  imports = [
    ./dynamic-hostname.nix
    ./vm-hostname-export.nix
    ./vm-hostname-setter.nix
  ];
}
