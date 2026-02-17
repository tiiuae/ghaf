# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# NET VM Features Module
#
# This module aggregates all NET VM feature modules and auto-includes them
# based on their respective conditions.
#
# Usage:
#   In profile's lib.nixosSystem call:
#     modules = [
#       inputs.self.nixosModules.netvm-base
#       inputs.self.nixosModules.netvm-features
#     ];
#
# Feature modules:
#   - hardware-passthrough.nix: nics config (from hostConfig)
#
{ ... }:
{
  _file = ./default.nix;

  imports = [
    ./hardware-passthrough.nix
  ];
}
