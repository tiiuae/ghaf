# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{ config, lib, ... }:
let
  # Ghaf systemd config
  cfg = config.ghaf.systemd;
  inherit (lib) mkIf mkOption types;
in
{
  _file = ./harden.nix;

  options.ghaf.systemd = {
    withHardenedConfigs = mkOption {
      description = "Enable common hardened configs.";
      type = types.bool;
      default = false;
    };
  };

  config = mkIf cfg.withHardenedConfigs {
    # Apply hardened systemd service configurations
    systemd = import ./hardened-configs;
  };
}
