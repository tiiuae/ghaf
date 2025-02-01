# Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{ config, lib, ... }:
let
  # Ghaf systemd config
  cfg = config.ghaf.systemd;
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
      (lib.mkIf cfg.withHardenedConfigs (import ./hardened-configs))

      # Set systemd log level
      { services."_global_".environment.SYSTEMD_LOG_LEVEL = cfg.logLevel; }
    ];
  };
}
