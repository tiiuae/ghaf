# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# VM Bases Module
#
# This module provides base VM configurations that can be extended via
# the NixOS module system's `extendModules` function.
#
# Each VM base is created with `lib.nixosSystem` and returns a result
# that includes the `.extendModules` function for composition.
#
# Usage:
#   let
#     guivmBase = vmBases.mkGuiVmBase { inherit lib inputs system; };
#     extendedGuivm = guivmBase.extendModules {
#       modules = [ ./extra-services.nix ];
#       specialArgs = { globalConfig = hostConfig.ghaf.global-config; };
#     };
#   in
#     microvm.vms.gui-vm.evaluatedConfig = extendedGuivm;
#
{ lib }:
{
  # GUI VM base configuration
  # Creates a lib.nixosSystem result with .extendModules
  mkGuiVmBase = import ./gui-vm.nix { inherit lib; };
}
