# Copyright 2024-2025 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{ config, lib, ... }:
let
  cfg = config.ghaf.security.apparmor;
in
{
  ## Option to enable Apparmor security
  options.ghaf.security.apparmor = {
    enable = lib.mkOption {
      description = ''
        Enable Apparmor security.
      '';
      type = lib.types.bool;
      default = false;
    };
  };

  imports = [
    ./profiles/google-chrome.nix
    ./profiles/ping.nix
  ];

  config = lib.mkIf cfg.enable {
    security.apparmor.enable = true;
    security.apparmor.killUnconfinedConfinables = lib.mkDefault true;
    services.dbus.apparmor = "enabled";
  };
}
