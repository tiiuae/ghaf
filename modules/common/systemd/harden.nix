# Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{ config, lib, ... }:
let
  # Ghaf systemd config
  cfg = config.ghaf.systemd;
  apply-service-configs = configs-dir: {
    services = lib.foldl' (
      services: s:
      let
        svc = builtins.replaceStrings [ ".nix" ] [ "" ] s;
      in
      services
      // lib.optionalAttrs (!builtins.elem "${svc}.service" cfg.excludedHardenedConfigs) {
        ${svc}.serviceConfig = import "${configs-dir}/${svc}.nix";
      }
    ) { } (builtins.attrNames (builtins.readDir configs-dir));
  };
in
{
  options.ghaf.systemd = {
    withHardenedConfigs = lib.mkOption {
      description = "Enable common hardened configs.";
      type = lib.types.bool;
      default = false;
    };

    excludedHardenedConfigs = lib.mkOption {
      default = [ ];
      type = lib.types.listOf lib.types.str;
      example = [ "sshd.service" ];
      description = ''
        A list of units to skip when applying hardened systemd service configurations.
        The main purpose of this is to provide a mechanism to exclude specific hardened
        configurations for fast debugging and problem resolution.
      '';
    };

    logLevel = lib.mkOption {
      description = ''
        Log Level for systemd services.
                  Available options: "emerg", "alert", "crit", "err", "warning", "info", "debug"
      '';
      type = lib.types.str;
      default = "info";
    };
  };

  config = {
    systemd = lib.mkMerge [
      # Apply hardened systemd service configurations
      (lib.mkIf cfg.withHardenedConfigs (apply-service-configs ./hardened-configs/common))

      # Apply release only service configurations
      (lib.mkIf (
        !cfg.withDebug && cfg.withHardenedConfigs
      ) (apply-service-configs ./hardened-configs/release))

      # Set systemd log level
      { services."_global_".environment.SYSTEMD_LOG_LEVEL = cfg.logLevel; }
    ];
  };
}
