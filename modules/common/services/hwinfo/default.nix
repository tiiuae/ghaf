# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# Hardware information modules
#
{
  _file = ./default.nix;

  imports = [
    ./host.nix
    ./guest.nix
  ];
}
