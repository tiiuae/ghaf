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
    environment = {
      systemPackages = [ pkgs.pulseaudio ];
      sessionVariables = rec {
        PULSE_SERVER = "${address}";
      };
    };
  };
}
