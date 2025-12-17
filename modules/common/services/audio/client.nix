# SPDX-FileCopyrightText: 2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  pkgs,
  config,
  lib,
  ...
}:
let
  cfg = config.ghaf.services.audio;
  inherit (lib)
    mkIf
    ;
  host = "gui-vm";
  address = "tcp:${host}:${toString cfg.hub.pulseaudioTcpPort}";

in
{
  config = mkIf (cfg.enable && (cfg.role == "client")) {
    environment = {
      systemPackages = [ pkgs.pulseaudio ];
      sessionVariables = {
        PULSE_SERVER = "${address}";
      };
      variables = {
        PULSE_SERVER = "${address}";
      };
    };
  };
}
