# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# GPU VM Configuration Module
#
# globalConfig pattern: global settings via globalConfig, host-specific
# (networking.hosts) via hostConfig. Self-contained (no `configHost`); platforms
# use evaluatedConfig with a profile's gpuvmBase.
#
# gpuvmBase (like netvmBase) is exported by the orin profile, which also wires
# evaluatedConfig. Inert unless that wiring is present: enable is true only when
# gpu_vm.enable is (Orin AGX), and the assertion below fires otherwise.
{
  config,
  lib,
  inputs,
  ...
}:
let
  vmName = "gpu-vm";

  cfg = config.ghaf.virtualization.microvm.gpuvm;
in
{
  _file = ./gpuvm.nix;

  options.ghaf.virtualization.microvm.gpuvm = {
    enable = lib.mkEnableOption "GpuVM";

    evaluatedConfig = lib.mkOption {
      type = lib.types.nullOr lib.types.unspecified;
      default = null;
      description = "Pre-evaluated NixOS configuration for GPU VM set via profile's gpuvmBase.extendModules.";
    };

    extraNetworking = lib.mkOption {
      type = lib.types.networking;
      description = "Extra Networking option";
      default = { };
    };
  };

  config = lib.mkMerge [
    {
      ghaf.virtualization.microvm.sysvm.vms.gpuvm = {
        inherit vmName;
        inherit (cfg) enable evaluatedConfig extraNetworking;
      };
    }
    (lib.mkIf cfg.enable {
      assertions = [
        {
          assertion = cfg.evaluatedConfig != null;
          message = ''
            ghaf.virtualization.microvm.gpuvm.evaluatedConfig must be set.
            Use a profile that provides gpuvmBase (orin).

            For Jetson (Orin AGX), the orin profile wires it as:
              gpuvm.evaluatedConfig = config.ghaf.profiles.orin.gpuvmBase.extendModules {
                modules = lib.ghaf.vm.applyVmConfig {
                  inherit config;
                  vmName = "gpuvm";
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
