# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# Disp VM Configuration Module
#
# globalConfig pattern: global settings via globalConfig specialArg,
# host-specific (networking.hosts) via hostConfig. Self-contained; all
# platforms use the evaluatedConfig pattern with a profile's dispvmBase.
#
# dispvmBase (like gpuvmBase) is exported by the orin profile, which also
# wires dispvm.evaluatedConfig. Inert unless that wiring is present: enable
# is only true when ghaf.hardware.nvidia.passthroughs.disp_vm.enable is true
# (Orin AGX only); the assertion below fires if enable is set without it.
{
  config,
  lib,
  inputs,
  ...
}:
let
  vmName = "disp-vm";

  cfg = config.ghaf.virtualization.microvm.dispvm;
in
{
  _file = ./dispvm.nix;

  options.ghaf.virtualization.microvm.dispvm = {
    enable = lib.mkEnableOption "DispVM";

    evaluatedConfig = lib.mkOption {
      type = lib.types.nullOr lib.types.unspecified;
      default = null;
      description = "Pre-evaluated NixOS configuration for Disp VM set via profile's dispvmBase.extendModules.";
    };

    extraNetworking = lib.mkOption {
      type = lib.types.networking;
      description = "Extra Networking option";
      default = { };
    };
  };

  config = lib.mkMerge [
    {
      ghaf.virtualization.microvm.sysvm.vms.dispvm = {
        inherit vmName;
        inherit (cfg) enable evaluatedConfig extraNetworking;
      };
    }
    (lib.mkIf cfg.enable {
      assertions = [
        {
          assertion = cfg.evaluatedConfig != null;
          message = ''
            ghaf.virtualization.microvm.dispvm.evaluatedConfig must be set.
            Use a profile that provides dispvmBase (orin).

            For Jetson (Orin AGX), the orin profile wires it as:
              dispvm.evaluatedConfig = config.ghaf.profiles.orin.dispvmBase.extendModules {
                modules = lib.ghaf.vm.applyVmConfig {
                  inherit config;
                  vmName = "dispvm";
                };
              };
          '';
        }
      ];

      ghaf.common = {
        extraNetworking.hosts.${vmName} = cfg.extraNetworking;
        policies = lib.mkIf cfg.evaluatedConfig.config.ghaf.givc.policyClient.enable {
          "${vmName}" = cfg.evaluatedConfig.config.ghaf.givc.policyClient.policies;
        };
        spire.agents = lib.mkIf cfg.evaluatedConfig.config.ghaf.security.spire.agents.downstream.enable {
          "${vmName}" = {
            inherit (cfg.evaluatedConfig.config.ghaf.security.spire.agents.downstream)
              nodeAttestationMode
              workloads
              ;
          };
        };
      };

      microvm.vms."${vmName}" = {
        autostart = !config.ghaf.microvm-boot.enable;
        restartIfChanged = false;
        inherit (inputs) nixpkgs;
        inherit (cfg) evaluatedConfig;
      };
    })
  ];
}
