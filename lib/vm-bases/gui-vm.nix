# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# GUI VM Base Configuration Factory
#
# Convenience wrapper that creates a base GUI VM using the guivm-base module.
# The result can be extended via .extendModules for profile-specific additions.
#
# Usage:
#   let
#     guivmBase = lib.ghaf.mkGuiVmBase { inherit lib inputs; system = "x86_64-linux"; };
#     extendedGuivm = guivmBase.extendModules {
#       modules = [ ./services ./programs ];
#       specialArgs = { inherit globalConfig hostConfig; };
#     };
#   in
#   microvm.vms.gui-vm.evaluatedConfig = extendedGuivm;
#
# Note: For layered composition, prefer using:
#   config.ghaf.profiles.laptop-x86.guivmBase.extendModules { ... }
# which provides hardware-specific configuration.
#
{ lib }:
{
  inputs,
  system ? "x86_64-linux",
  # Initial globalConfig and hostConfig - can be overridden via extendModules
  globalConfig ? { },
  hostConfig ? { },
}:
lib.nixosSystem {
  inherit system;

  specialArgs = {
    inherit
      lib
      inputs
      globalConfig
      hostConfig
      ;
  };

  modules = [
    inputs.microvm.nixosModules.microvm
    inputs.self.nixosModules.guivm-base
  ];
}
