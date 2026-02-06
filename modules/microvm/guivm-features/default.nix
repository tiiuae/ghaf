# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# GUI VM Features Module
#
# This module aggregates all GUI VM feature modules and auto-includes them
# based on their respective conditions.
#
# Usage:
#   In profile's lib.nixosSystem call:
#     modules = [
#       inputs.self.nixosModules.guivm-base
#       inputs.self.nixosModules.guivm-features
#     ];
#
# Feature modules:
#   - hardware-passthrough.nix: GPU/input/kernel/QEMU config (from hostConfig)
#
{ ... }:
{
  _file = ./default.nix;

  imports = [
    ./hardware-passthrough.nix
  ];
}
