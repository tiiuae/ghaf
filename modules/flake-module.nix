# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# Modules to be exported from Flake
#
{
  imports = [
    ./partitioning/flake-module.nix
    ./givc/flake-module.nix
    ./hardware/flake-module.nix
    ./microvm/flake-module.nix
    ./reference/hardware/flake-module.nix
    ./profiles/flake-module.nix
    ./common/flake-module.nix
    ./development/flake-module.nix
    ./desktop/flake-module.nix
    ./reference/flake-module.nix
  ];
}
