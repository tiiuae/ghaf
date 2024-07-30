# Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
{
  config,
  pkgs,
  lib,
  ...
}: let
  cfg = config.ghaf.services.audio;
  inherit (lib) mkIf mkEnableOption mkOption types;
in {
  options.ghaf.services.audio = {
    enable = mkEnableOption "Enable audio service for audio VM";
    pulseaudioTcpPort = mkOption {
      type = types.int;
      default = 4713;
      description = "TCP port used by Pipewire-pulseaudio service";
    };
  };

  config = mkIf cfg.enable {
    # Enable pipewire service for audioVM with pulseaudio support
    security.rtkit.enable = true;
    hardware.firmware = [pkgs.sof-firmware];
    services.pipewire = {
      enable = true;
      pulse.enable = true;
      systemWide = true;

      configPackages = [
        (pkgs.writeTextDir "share/pipewire/pipewire.conf.d/10-remote-simple.conf" ''
          context.modules = [
            {   name = libpipewire-module-protocol-pulse
                args = {
                  server.address = [
                      "tcp:4713"    # IPv4 and IPv6 on all addresses
                  ];
                  pulse.min.req          = 128/48000;     # 2.7ms
                  pulse.default.req      = 960/48000;     # 20 milliseconds
                  pulse.min.frag         = 128/48000;     # 2.7ms
                  pulse.default.frag     = 512/48000;     # ~10 ms
                  pulse.default.tlength  = 512/48000;     # ~10 ms
                  pulse.min.quantum      = 128/48000;     # 2.7ms
                }
            }
          ];
        '')
      ];
    };

    hardware.pulseaudio.extraConfig = ''
      # Set sink and source default max volume to about 75% (0-65536)
      set-sink-volume @DEFAULT_SINK@ 48000
      set-source-volume @DEFAULT_SOURCE@ 48000
    '';

    # Allow ghaf user to access pulseaudio and pipewire
    users.extraUsers.ghaf.extraGroups = ["audio" "video" "pulse-access" "pipewire"];

    # Dummy service to get pipewire and pulseaudio services started at boot
    # Normally Pipewire and pulseaudio are started when they are needed by user,
    # We don't have users in audiovm so we need to give PW/PA a slight kick..
    # This calls pulseaudios pa-info binary to get information about pulseaudio current
    # state which starts pipewire-pulseaudio service in the process.
    systemd.services.pulseaudio-starter = {
      after = ["pipewire.service" "network-online.target"];
      requires = ["pipewire.service" "network-online.target"];
      wantedBy = ["default.target"];
      path = [pkgs.coreutils];
      enable = true;
      serviceConfig = {
        User = "ghaf";
        Group = "ghaf";
      };
      script = ''${pkgs.pulseaudio}/bin/pa-info > /dev/null 2>&1'';
    };

    # Open TCP port for the PDF XDG socket
    networking.firewall.allowedTCPPorts = [cfg.pulseaudioTcpPort];
  };
}
