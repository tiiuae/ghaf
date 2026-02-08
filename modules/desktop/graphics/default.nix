# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  _file = ./default.nix;

  imports = [
    ./cosmic
    ./launchers.nix
    ./login-manager.nix
    ./boot.nix
    ./screen-recorder.nix
  ];
}
