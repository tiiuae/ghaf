# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# GUI VM Desktop Features Module
#
# This module aggregates all GUI VM feature modules and auto-includes them
# based on their respective feature flags in globalConfig.
#
# Usage:
#   In profile's extendModules call:
#     guivmBase.extendModules {
#       modules = [
#         inputs.self.nixosModules.guivm-desktop-features
#       ];
#     }
#
# Feature modules auto-include based on:
#   - boot-ui.nix: globalConfig.graphics.boot.enable
#   - shared-folders.nix: config.ghaf.storagevm.shared-folders.enable (VM-local)
#   - shared-mem.nix: globalConfig.shm.enable
#   - ghaf-intro.nix: hostConfig.reference.desktop.ghaf-intro.enable
#
# Note: Waypipe configuration is not included here as it requires host-level
# access to microvm.vms for iterating over AppVMs. It's contributed via
# ghaf.hardware.definition.guivm.extraModules from the appvm.nix module.
#
{ ... }:
{
  _file = ./default.nix;

  imports = [
    # All feature modules use mkIf internally to conditionally enable
    # based on their respective globalConfig flags
    ./boot-ui.nix
    ./shared-folders.nix
    ./shared-mem.nix
    ./ghaf-intro.nix
  ];
}
