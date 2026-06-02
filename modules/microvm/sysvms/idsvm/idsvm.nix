# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# IDS VM Configuration Module
#
# This module requires evaluatedConfig to be set via profile composition.
# The actual VM configuration is in idsvm-base.nix.
#
# Usage in profiles:
#   ghaf.virtualization.microvm.idsvm.evaluatedConfig =
#     config.ghaf.profiles.laptop-x86.idsvmBase.extendModules { ... };
#
{
  config,
  lib,
  inputs,
  ...
}:
let
  vmName = "ids-vm";
  cfg = config.ghaf.virtualization.microvm.idsvm;
in
{
  _file = ./idsvm.nix;

  imports = [
    ./mitmproxy
  ];

  options.ghaf.virtualization.microvm.idsvm = {
    enable = lib.mkEnableOption "Whether to enable IDS-VM on the system";

    passiveMonitor = {
      enable = lib.mkEnableOption "passive traffic monitoring via TC tap mirror from net-vm";
      external = lib.mkEnableOption "mirror external (physical NIC) traffic";
      internal = lib.mkEnableOption "mirror internal (inter-VM) traffic";
      snaplen = lib.mkOption {
        type = lib.types.nullOr lib.types.ints.positive;
        default = null;
        example = 128;
        description = ''
          Truncate mirrored packets to this many bytes (header-only capture)
          before they leave net-vm, via an eBPF classifier on the `mirror`
          tap's egress. null (default) mirrors full packets, unchanged.
        '';
      };
      netem = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        example = "slot 10ms 20ms packets 300 limit 2000";
        description = ''
          netem qdisc params applied to net-vm's `mirror` tap. null (default)
          leaves trafficMirror.sender.netem at its own default; set this to
          override with a value validated for this specific target's
          hardware (see modules/microvm/common/traffic-mirror.nix
          sender.netem for why this isn't safe to share blindly across
          targets).
        '';
      };
    };

    evaluatedConfig = lib.mkOption {
      type = lib.types.nullOr lib.types.unspecified;
      default = null;
      description = ''
        Pre-evaluated NixOS configuration for IDS VM.
        Profiles must set this using idsvmBase.extendModules from a profile
        (e.g., laptop-x86).
      '';
    };

    extraNetworking = lib.mkOption {
      type = lib.types.networking;
      description = "Extra Networking option";
      default = { };
    };
  };

  config = lib.mkMerge [
    {
      ghaf.virtualization.microvm.sysvm.vms.idsvm = {
        inherit vmName;
        inherit (cfg) enable evaluatedConfig extraNetworking;
      };

      ghaf.virtualization.microvm.host.trafficMirror.enable = lib.mkDefault cfg.passiveMonitor.enable;
    }
    (lib.mkIf cfg.enable {
      assertions = [
        {
          assertion = cfg.evaluatedConfig != null;
          message = ''
            ghaf.virtualization.microvm.idsvm.evaluatedConfig must be set.
            Use idsvmBase.extendModules from a profile (laptop-x86, etc.).
            Example:
              ghaf.virtualization.microvm.idsvm.evaluatedConfig =
                config.ghaf.profiles.laptop-x86.idsvmBase.extendModules { modules = [...]; };
          '';
        }
      ];

      ghaf.common = {
        extraNetworking.hosts.${vmName} = cfg.extraNetworking;
        policies = lib.mkIf cfg.evaluatedConfig.config.ghaf.givc.policyClient.enable {
          "${vmName}" = cfg.evaluatedConfig.config.ghaf.givc.policyClient.policies;
        };
        spire.agents =
          let
            localAgent = cfg.evaluatedConfig.config.ghaf.security.spire.agents.downstream or null;
          in
          lib.mkIf (localAgent != null && localAgent.enable) {
            "${vmName}" = {
              inherit (localAgent) nodeAttestationMode workloads;
            };
          };
      };

      microvm.vms."${vmName}" = {
        autostart = true;
        inherit (inputs) nixpkgs;
        inherit (cfg) evaluatedConfig;
      };
    })
  ];
}
