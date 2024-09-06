# Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
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
  address = "tcp:${audiovmHost}:${toString audiovmPort}";
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
  };

  config = lib.mkIf cfg.enable {
    security.rtkit.enable = true;
    users.extraUsers.ghaf.extraGroups = [
      "audio"
      "video"
    ];

    hardware.pulseaudio = {
      enable = true;
      extraConfig = ''
        load-module module-tunnel-sink-new sink_name=${cfg.name}.speaker server=${address} reconnect_interval_ms=${toString reconnectMs}
        load-module module-tunnel-source-new source_name=${cfg.name}.mic server=${address} reconnect_interval_ms=${toString reconnectMs}
      '';
      package = pkgs.pulseaudio-ghaf;
    };
  };
}
