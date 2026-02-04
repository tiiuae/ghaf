# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  _file = ./default.nix;

  imports = [
    ./active-directory.nix
    ./admin.nix
    ./ad-users.nix
    ./auxiliary.nix
    ./profiles.nix
    ./homed.nix
    ./managed.nix
  ];
}
