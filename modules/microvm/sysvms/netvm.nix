# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# Net VM Configuration Module
#
# This module uses the globalConfig pattern:
# - Global settings (debug, development, logging, storage) come via globalConfig specialArg
# - Host-specific settings (networking.hosts) come via hostConfig specialArg
#
# The VM configuration is self-contained and does not reference `configHost`.
# All platforms must use the evaluatedConfig pattern with a profile's netvmBase.
#
{
  config,
  lib,
  inputs,
  ...
}:
let
  vmName = "net-vm";
  cfg = config.ghaf.virtualization.microvm.netvm;
in
{
  _file = ./netvm.nix;

  options.ghaf.virtualization.microvm.netvm = {
    enable = lib.mkEnableOption "NetVM";

    evaluatedConfig = lib.mkOption {
      type = lib.types.nullOr lib.types.unspecified;
      default = null;
      description = "Pre-evaluated NixOS configuration for Net VM set via profile's netvmBase.extendModules.";
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
          ghaf.virtualization.microvm.netvm.evaluatedConfig must be set.
          Use a profile that provides netvmBase (laptop-x86 or orin).

          For x86 laptops:
            netvm.evaluatedConfig = config.ghaf.profiles.laptop-x86.netvmBase.extendModules {
              modules = config.ghaf.hardware.definition.netvm.extraModules or [];
            };

          For Jetson (Orin):
            netvm.evaluatedConfig = config.ghaf.profiles.orin.netvmBase.extendModules {
              modules = config.ghaf.hardware.definition.netvm.extraModules or [];
            };
        '';
      }
    ];

    ghaf.common.extraNetworking.hosts.${vmName} = cfg.extraNetworking;

    microvm.vms."${vmName}" = {
      autostart = !config.ghaf.microvm-boot.enable;
      restartIfChanged = false;
      inherit (inputs) nixpkgs;
      inherit (cfg) evaluatedConfig;
    };
  };
}
