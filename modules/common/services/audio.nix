# Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
{
  config,
  pkgs,
  lib,
  ...
}:
let
  cfg = config.ghaf.services.audio;
  inherit (lib)
    mkIf
    mkEnableOption
    mkOption
    types
    ;
in
{
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
    hardware.firmware = [ pkgs.sof-firmware ];
    services.pipewire = {
      enable = true;
      pulse.enable = true;
      alsa.enable = config.ghaf.development.debug.tools.enable;
      systemWide = true;
      extraConfig = {
        pipewire."10-remote-simple" = {
          "context.modules" = [
            {
              name = "libpipewire-module-protocol-pulse";
              args = {
                # Enable TCP socket for VMs pulseaudio clients
                "server.address" = [
                  {
                    address = "tcp:${toString cfg.pulseaudioTcpPort}";
                    "client.access" = "unrestricted";
                  }
                ];
                "pulse.min.req" = "1024/48000";
                "pulse.min.quantum" = "1024/48000";
                "pulse.idle.timeout" = "3";
              };
            }
          ];
        };
      };
      # Disable the auto-switching to the low-quality HSP profile
      wireplumber.extraConfig.disable-autoswitch = {
        "wireplumber.settings" = {
          "bluetooth.autoswitch-to-headset-profile" = "false";
        };
      };
    };

    # Allow ghaf user to access pulseaudio and pipewire
    users.extraUsers.ghaf.extraGroups = [
      "audio"
      "video"
      "pipewire"
    ];

    # Start pipewire on system boot
    systemd.services.pipewire.wantedBy = [ "multi-user.target" ];

    # Open TCP port for the pipewire pulseaudio socket
    networking.firewall.allowedTCPPorts = [ cfg.pulseaudioTcpPort ];
  };
}
