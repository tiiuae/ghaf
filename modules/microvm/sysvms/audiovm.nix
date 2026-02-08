# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# Audio VM Configuration Module
#
# This module requires evaluatedConfig to be set via profile composition.
# The actual VM configuration is in audiovm-base.nix.
#
# Usage in profiles:
#   ghaf.virtualization.microvm.audiovm.evaluatedConfig =
#     config.ghaf.profiles.laptop-x86.audiovmBase.extendModules { ... };
#
{
  config,
  lib,
  inputs,
  ...
}:
let
  vmName = "audio-vm";
  cfg = config.ghaf.virtualization.microvm.audiovm;
in
{
  _file = ./audiovm.nix;

  options.ghaf.virtualization.microvm.audiovm = {
    enable = lib.mkEnableOption "AudioVM";

    evaluatedConfig = lib.mkOption {
      type = lib.types.nullOr lib.types.unspecified;
      default = null;
      description = ''
        Pre-evaluated NixOS configuration for Audio VM.
        Profiles must set this using audiovmBase.extendModules from a profile
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
          ghaf.virtualization.microvm.audiovm.evaluatedConfig must be set.
          Use audiovmBase.extendModules from a profile (laptop-x86, orin, etc.).
          Example:
            ghaf.virtualization.microvm.audiovm.evaluatedConfig =
              config.ghaf.profiles.laptop-x86.audiovmBase.extendModules { modules = [...]; };
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
