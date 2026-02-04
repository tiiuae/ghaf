# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# Admin VM Configuration Module
#
# This module requires evaluatedConfig to be set via profile composition.
# The actual VM configuration is in adminvm-base.nix.
#
# Usage in profiles:
#   ghaf.virtualization.microvm.adminvm.evaluatedConfig =
#     config.ghaf.profiles.laptop-x86.adminvmBase.extendModules { ... };
#
{
  config,
  lib,
  inputs,
  ...
}:
let
  vmName = "admin-vm";
  cfg = config.ghaf.virtualization.microvm.adminvm;
in
{
  _file = ./adminvm.nix;

  options.ghaf.virtualization.microvm.adminvm = {
    enable = lib.mkEnableOption "AdminVM";

    evaluatedConfig = lib.mkOption {
      type = lib.types.nullOr lib.types.unspecified;
      default = null;
      description = ''
        Pre-evaluated Admin VM NixOS configuration.
        Profiles must set this using adminvmBase.extendModules from a profile
        (e.g., laptop-x86 or orin).
      '';
    };

    extraNetworking = lib.mkOption {
      type = lib.types.networking;
      description = "Extra Networking option";
      default = { };
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = cfg.evaluatedConfig != null;
        message = ''
          ghaf.virtualization.microvm.adminvm.evaluatedConfig must be set.
          Use adminvmBase.extendModules from a profile (laptop-x86, orin, etc.).
          Example:
            ghaf.virtualization.microvm.adminvm.evaluatedConfig =
              config.ghaf.profiles.laptop-x86.adminvmBase.extendModules { modules = [...]; };
        '';
      }
    ];

    ghaf.common.extraNetworking.hosts.${vmName} = cfg.extraNetworking;

    microvm.vms."${vmName}" = {
      autostart = true;
      inherit (inputs) nixpkgs;
      inherit (cfg) evaluatedConfig;
    };
  };
}
