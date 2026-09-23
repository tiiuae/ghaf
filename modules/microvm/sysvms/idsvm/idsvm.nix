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
      enable = lib.mkEnableOption "passive traffic monitoring";
      external = lib.mkEnableOption "mirror external (physical NIC) traffic";
      internal = lib.mkEnableOption "mirror internal (inter-VM) traffic";
      snaplen = lib.mkOption {
        type = lib.types.nullOr lib.types.ints.positive;
        default = null;
        example = 128;
        description = ''
          Truncate mirrored packets to this many bytes, capturing headers
          only. An eBPF classifier on monitored vm's `mirror` tap egress does the
          truncation, before the packets leave monitored vm.
        '';
      };
      netem = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        example = "slot 10ms 20ms packets 300 limit 2000";
        description = ''
          netem qdisc parameters applied to `mirror` tap.

          Leave as null to keep whatever `trafficMirror.sender.netem`
          defaults to. Set it to override that default with a value
          validated for this target's hardware.
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

      microvm.vms."${vmName}" = {
        autostart = true;
        inherit (inputs) nixpkgs;
        inherit (cfg) evaluatedConfig;
      };
    })
  ];
}
