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
    mkMerge
    optionalAttrs
    hasAttr
    ;
in
{
  options.ghaf.services.audio = {
    enable = mkEnableOption "Enable audio service for audio VM";
    debug = mkOption {
      type = types.bool;
      default = config.ghaf.profiles.debug.enable;
      defaultText = "config.ghaf.profiles.debug.enable";
      description = "Enable debug logs for pipewire and wireplumber";
    };
    pulseaudioTcpPort = mkOption {
      type = types.int;
      default = 4713;
      description = "TCP port used by Pipewire-pulseaudio service";
    };
    pulseaudioTcpControlPort = mkOption {
      type = types.int;
      default = 4714;
      description = "TCP port used by Pipewire-pulseaudio control";
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
        pipewire."10-remote-pulseaudio" = {
          "context.modules" = [
            {
              name = "libpipewire-module-protocol-pulse";
              args = {
                # Enable TCP socket for VMs pulseaudio clients
                "server.address" = [
                  {
                    address = "tcp:0.0.0.0:${toString cfg.pulseaudioTcpPort}";
                    "client.access" = "restricted";
                  }
                ];
                "pulse.min.req" = "1024/48000";
                "pulse.min.quantum" = "1024/48000";
                "pulse.idle.timeout" = "3";
              };
            }
            {
              name = "libpipewire-module-protocol-pulse";
              args = {
                # Enable TCP socket for VMs pulseaudio clients
                "server.address" = [
                  {
                    address = "tcp:0.0.0.0:${toString cfg.pulseaudioTcpControlPort}";
                    "client.access" = "unrestricted";
                  }
                ];
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
        # Enable alsa ACP auto profile for headphones
        "monitor.alsa.properties" = {
          "alsa.use-acp" = "true";
          "acp.auto-profile" = "true";
          "acp.auto-port" = "true";
        };
      };
    };

    systemd.services =
      let
        debugLevel = if cfg.debug then "3" else "1";
      in
      {
        pipewire = {
          wantedBy = [ "multi-user.target" ];
          environment.PIPEWIRE_DEBUG = debugLevel;
        };
        wireplumber.environment.WIREPLUMBER_DEBUG = debugLevel;
      };

    ghaf = mkMerge [
      {
        # Open TCP port for the pipewire pulseaudio socket
        firewall.allowedTCPPorts = with cfg; [
          pulseaudioTcpPort
          pulseaudioTcpControlPort
        ];
      }
      # Enable persistent storage for pipewire state to restore settings on boot
      (optionalAttrs (hasAttr "storagevm" config.ghaf) {
        storagevm.directories = [
          {
            directory = "/var/lib/pipewire";
            user = "pipewire";
            group = "pipewire";
            mode = "0700";
          }
        ];
      })
    ];
  };
}
