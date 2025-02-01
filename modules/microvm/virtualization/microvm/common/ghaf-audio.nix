# Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  configHost,
}:
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.ghaf.ghaf-audio;
  audiovmHost = "audio-vm";
  audiovmPort = config.ghaf.services.audio.pulseaudioTcpPort;
  address =
    if configHost.ghaf.shm.service.audio.enabled then
      "unix:${configHost.ghaf.shm.service.audio.clientSocketPath}"
    else
      "tcp:${audiovmHost}:${toString audiovmPort}";
  reconnectMs = 1000;
in
{
  options.ghaf.ghaf-audio = with lib; {
    enable = mkEnableOption "Ghaf audio support for application virtual machine.";

    name = mkOption {
      description = ''
        Basename of corresponding virtual machine audio channel.
      '';
      type = types.str;
    };

    useTunneling = mkEnableOption "Enable local pulseaudio with tunneling";
  };

  config = lib.mkIf cfg.enable {
    security.rtkit.enable = cfg.useTunneling;
    ghaf.users.appUser.extraGroups = lib.mkIf cfg.useTunneling [
      "audio"
      "video"
    ];

    hardware.pulseaudio = lib.mkIf cfg.useTunneling {
      enable = true;
      extraConfig = ''
        load-module module-tunnel-sink sink_name=${cfg.name}.speaker server=${address} reconnect_interval_ms=${toString reconnectMs}
        load-module module-tunnel-source source_name=${cfg.name}.mic server=${address} reconnect_interval_ms=${toString reconnectMs}
      '';
    };

    environment = lib.mkIf (!cfg.useTunneling) {
      systemPackages = [ pkgs.pulseaudio ];
      sessionVariables = rec {
        PULSE_SERVER = "${address}";
      };
    };
  };
}
