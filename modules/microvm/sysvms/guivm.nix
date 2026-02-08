# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# GUI VM Configuration Module
#
# This module requires evaluatedConfig to be set via profile composition.
# The actual VM configuration is in guivm-base.nix.
#
# Usage in profiles:
#   ghaf.virtualization.microvm.guivm.evaluatedConfig =
#     lib.ghaf.vm.applyVmConfig { ... guivmBase.extendModules { ... } ... };
#
{
  config,
  lib,
  inputs,
  ...
}:
let
  vmName = "gui-vm";
  cfg = config.ghaf.virtualization.microvm.guivm;
in
{
  _file = ./guivm.nix;

  options.ghaf.virtualization.microvm.guivm = {
    enable = lib.mkEnableOption "GUIVM";

    evaluatedConfig = lib.mkOption {
      type = lib.types.nullOr lib.types.unspecified;
      default = null;
      description = ''
        Pre-evaluated GUI VM configuration from extendModules.
        Profiles must set this by extending guivmBase from a profile
        (e.g., laptop-x86 or orin).
      '';
    };

    extraNetworking = lib.mkOption {
      type = lib.types.networking;
      description = "Extra Networking option";
      default = { };
    };

    applications = lib.mkOption {
      description = ''
        Applications to include in the GUIVM
      '';
      type = lib.types.listOf (
        lib.types.submodule {
          options = {
            name = lib.mkOption {
              type = lib.types.str;
              description = "The name of the application";
            };
            description = lib.mkOption {
              type = lib.types.str;
              description = "A brief description of the application";
            };
            icon = lib.mkOption {
              type = lib.types.str;
              description = "Application icon";
              default = null;
            };
            command = lib.mkOption {
              type = lib.types.str;
              description = "The command to run the application";
              default = null;
            };
          };
        }
      );
      default = [ ];
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = cfg.evaluatedConfig != null;
        message = ''
          ghaf.virtualization.microvm.guivm.evaluatedConfig must be set.
          Use guivmBase.extendModules from a profile (laptop-x86, orin, etc.).
          Example:
            ghaf.virtualization.microvm.guivm.evaluatedConfig =
              lib.ghaf.vm.applyVmConfig {
                baseConfig = config.ghaf.profiles.laptop-x86.guivmBase.extendModules { ... };
                ...
              };
        '';
      }
    ];

    ghaf.common.extraNetworking.hosts.${vmName} = cfg.extraNetworking;

    microvm.vms."${vmName}" = {
      autostart = !config.ghaf.microvm-boot.enable;
      inherit (inputs) nixpkgs;
      inherit (cfg) evaluatedConfig;
    };
  };
}
