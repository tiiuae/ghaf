# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  description,
  optionName,
  vmName,
}:
{
  config,
  lib,
  inputs,
  ...
}:
let
  cfg = config.ghaf.virtualization.microvm.${optionName};
in
{
  _file = ./gpu-display-vm.nix;

  options.ghaf.virtualization.microvm.${optionName} = {
    enable = lib.mkEnableOption description;
    evaluatedConfig = lib.mkOption {
      type = lib.types.nullOr lib.types.unspecified;
      default = null;
      description = "Pre-evaluated NixOS configuration for ${description}.";
    };
    extraNetworking = lib.mkOption {
      type = lib.types.networking;
      default = { };
      description = "Extra networking configuration for ${description}.";
    };
  };

  config = lib.mkMerge [
    {
      ghaf.virtualization.microvm.sysvm.vms.${optionName} = {
        inherit vmName;
        inherit (cfg) enable evaluatedConfig extraNetworking;
      };
    }
    (lib.mkIf cfg.enable {
      assertions = [
        {
          assertion = cfg.evaluatedConfig != null;
          message = "ghaf.virtualization.microvm.${optionName}.evaluatedConfig must be set by the active platform profile.";
        }
      ];
      microvm.vms.${vmName} = {
        autostart = !config.ghaf.microvm-boot.enable;
        restartIfChanged = false;
        inherit (inputs) nixpkgs;
        inherit (cfg) evaluatedConfig;
      };
    })
  ];
}
