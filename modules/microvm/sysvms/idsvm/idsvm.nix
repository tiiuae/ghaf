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

  config = lib.mkIf cfg.enable {
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

    ghaf.common.extraNetworking.hosts.${vmName} = cfg.extraNetworking;

    microvm.vms."${vmName}" = {
      autostart = true;
      inherit (inputs) nixpkgs;
      inherit (cfg) evaluatedConfig;
    };
  };
}
