# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# Audio VM Features Module
#
# This module aggregates all Audio VM feature modules and auto-includes them
# based on their respective feature flags in hostConfig.
#
# Usage:
#   In profile's lib.nixosSystem call:
#     modules = [
#       inputs.self.nixosModules.audiovm-base
#       inputs.self.nixosModules.audiovm-features
#     ];
#
# Feature modules auto-include based on:
#   - bluetooth.nix: hostConfig.audiovm.audio (from microvm options)
#   - xpadneo.nix: hostConfig.audiovm.audio (from microvm options)
#   - hardware-passthrough.nix: hostConfig has hardware devices
#
{ ... }:
{
  _file = ./default.nix;

  imports = [
    # All feature modules use mkIf internally to conditionally enable
    # based on their respective hostConfig flags
    ./bluetooth.nix
    ./xpadneo.nix
    ./hardware-passthrough.nix
  ];
}
