# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# Peripherals VM Configuration Module
#
# This module requires evaluatedConfig to be set via profile composition.
# The actual VM configuration is in peripheralsvm-base.nix.
#
# Usage in profiles:
#   ghaf.virtualization.microvm.peripheralsvm.evaluatedConfig =
#     config.ghaf.profiles.laptop-x86.peripheralsvmBase.extendModules { ... };
#
{
  config,
  lib,
  inputs,
  ...
}:
let
  vmName = "periph-vm";
  cfg = config.ghaf.virtualization.microvm.peripheralsvm;
  enable = config.ghaf.services.usb-filtering.enable;
  targetVms = config.ghaf.services.usb-filtering.targetVms;
in
{
  _file = ./peripheralsvm.nix;

  options.ghaf.virtualization.microvm.peripheralsvm = {
    enable = lib.mkEnableOption "PeripheralsVM" // {
      default = enable;
    };
    evaluatedConfig = lib.mkOption {
      type = lib.types.nullOr lib.types.unspecified;
      default = null;
      description = ''
        Pre-evaluated NixOS configuration for Peripherals VM.
        Profiles must set this using peripheralsvmBase.extendModules from a profile
        (e.g., laptop-x86 or orin).
      '';
    };

    extraNetworking = lib.mkOption {
      type = lib.types.networking;
      default = { };
      description = "Extra networking configuration for this system VM.";
    };

    usbip = {
      enable = lib.mkEnableOption "USB/IP support for forwarding USB devices to target VMs" // {
        default = enable;
      };

      targetVms = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = targetVms;
        description = "List of VM names that USB devices should be forwarded to via USB/IP.";
      };

      port = lib.mkOption {
        type = lib.types.port;
        default = 3240;
        description = "TCP port used by the USB/IP server.";
      };
    };
  };

  config = lib.mkMerge [
    {
      ghaf.virtualization.microvm.sysvm.vms.peripheralsvm = {
        inherit vmName enable;
        inherit (cfg) evaluatedConfig extraNetworking;
      };
    }
    (lib.mkIf cfg.enable {
      assertions = [
        {
          assertion = cfg.evaluatedConfig != null;
          message = ''
            ghaf.virtualization.microvm.peripheralsvm.evaluatedConfig must be set.
            Use peripheralsvmBase.extendModules from a profile (laptop-x86, orin, etc.).
            Example:
              ghaf.virtualization.microvm.peripheralsvm.evaluatedConfig =
                config.ghaf.profiles.laptop-x86.peripheralsvmBase.extendModules { modules = [...]; };
          '';
        }
      ];

      ghaf.common = {
        extraNetworking.hosts.${vmName} = cfg.extraNetworking;
        policies = lib.mkIf cfg.evaluatedConfig.config.ghaf.givc.policyClient.enable {
          "${vmName}" = cfg.evaluatedConfig.config.ghaf.givc.policyClient.policies;
        };
        spire.agents = lib.mkIf cfg.evaluatedConfig.config.ghaf.security.spire.agent.enable {
          "${vmName}" = {
            inherit (cfg.evaluatedConfig.config.ghaf.security.spire.agent) nodeAttestationMode workloads;
          };
        };
      };

      # Open USB/IP port in the firewall for each target VM
      ghaf.firewall = lib.mkIf cfg.usbip.enable {
        allowedTCPPorts = [ cfg.usbip.port ];
      };

      microvm.vms."${vmName}" = {
        autostart = !config.ghaf.microvm-boot.enable;
        inherit (inputs) nixpkgs;
        inherit (cfg) evaluatedConfig;
      };
    })
  ];
}
