# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{ config, lib, ... }:
let
  # Ghaf systemd config
  cfg = config.ghaf.systemd;
  inherit (lib) mkEnableOption mkIf;
in
{
  _file = ./harden.nix;

  options.ghaf.systemd = {
    withHardenedConfigs = mkEnableOption "common hardened configs";
  };

  config = mkIf cfg.withHardenedConfigs {
    # Apply hardened systemd service configurations
    systemd = import ./hardened-configs;
  };
}
