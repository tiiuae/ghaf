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
  host = "gui-vm";
  address = "tcp:${host}:${toString cfg.hub.pulseaudioTcpPort}";

in
{
  options.ghaf.services.audio = {
    client = {
      remotePulseServerAddress = lib.mkOption {
        type = lib.types.str;
        default = address;
        defaultText = "tcp:gui-vm:4715";
        description = ''
          Address of the remote PulseAudio server to connect to.

          This should point to the Ghaf audio hub server.
        '';
      };
    };
  };
  config = lib.mkIf (cfg.enable && (cfg.role == "client")) {
    environment = {
      systemPackages = [ pkgs.pulseaudio ];
      sessionVariables = {
        PULSE_SERVER = "${cfg.client.remotePulseServerAddress}";
      };
      variables = {
        PULSE_SERVER = "${cfg.client.remotePulseServerAddress}";
      };
    };
  };
}
