# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.ghaf.ghaf-audio;

  inherit (lib)
    mkIf
    mkEnableOption
    mkOption
    types
    ;

  audiovmHost = "audio-vm";
  audiovmPort = config.ghaf.services.audio.pulseaudioTcpPort;
  address = "tcp:${audiovmHost}:${toString audiovmPort}";
  reconnectMs = 1000;
in
{
  options.ghaf.ghaf-audio = {
    enable = mkEnableOption "Ghaf audio support for application virtual machine.";

    name = mkOption {
      description = ''
        Basename of corresponding virtual machine audio channel.
      '';
      type = types.str;
    };

    useTunneling = mkEnableOption "Enable local pulseaudio with tunneling";
  };

  config = mkIf cfg.enable {
    security.rtkit.enable = cfg.useTunneling;
    ghaf.users.appUser.extraGroups = mkIf cfg.useTunneling [
      "audio"
      "video"
    ];

    hardware.pulseaudio = mkIf cfg.useTunneling {
      enable = true;
      extraConfig = ''
        load-module module-tunnel-sink sink_name=${cfg.name}.speaker server=${address} reconnect_interval_ms=${toString reconnectMs}
        load-module module-tunnel-source source_name=${cfg.name}.mic server=${address} reconnect_interval_ms=${toString reconnectMs}
      '';
    };

    environment = mkIf (!cfg.useTunneling) {
      systemPackages = [ pkgs.pulseaudio ];
      sessionVariables = {
        PULSE_SERVER = "${address}";
      };
    };
  };
}
