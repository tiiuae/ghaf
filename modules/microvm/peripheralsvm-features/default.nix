# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# Peripherals VM Features Module
#
# This module aggregates all Peripherals VM feature modules and auto-includes them
# based on their respective conditions.
#
# Usage:
#   In profile's lib.nixosSystem call:
#     modules = [
#       inputs.self.nixosModules.peripheralsvm-base
#       inputs.self.nixosModules.peripheralsvm-features
#     ];
#
# Feature modules:
#   - hardware-passthrough.nix: usb config (from hostConfig)
#
{ ... }:
{
  _file = ./default.nix;

  imports = [
    ./hardware-passthrough.nix
  ];
}
