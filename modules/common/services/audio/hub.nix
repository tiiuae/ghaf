# SPDX-FileCopyrightText: 2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0

# Ghaf audio bridge configuration
# This module sets discovers all sinks and sources from the main audio server.
# This module should be enabled on the system the user has full access to, in order to control audio.

# Edge nodes (app VMs) will connect to this audio server to get audio output and input.
{
  pkgs,
  config,
  lib,
  ...
}:
let
  cfg = config.ghaf.services.audio;
  inherit (lib)
    mkEnableOption
    mkIf
    mkMerge
    mkOption
    types
    ;

in
{
  options.ghaf.services.audio = {
    hub = mkEnableOption "";
    guiPulseaudioTcpPort = mkOption {
      type = types.int;
      default = 4715;
      description = "TCP port used by Pipewire-pulseaudio control on gui-vm";
    };
  };

  config = mkIf cfg.hub {
    security.rtkit.enable = true;
    hardware.firmware = [ pkgs.sof-firmware ];

    environment.systemPackages = with pkgs; [
      pavucontrol
    ];

    services.avahi = {
      enable = true;
      ipv6 = false;
      nssmdns4 = true;
      publish = {
        enable = true;
        userServices = true;
        addresses = true;
      };
      openFirewall = true;
      allowInterfaces = [ "ethint0" ];
    };

    services.resolved = {
      enable = true;

      llmnr = "false";

      extraConfig = ''
        MulticastDNS=no
        DNSStubListener=yes
      '';
    };

    services.pipewire = {
      enable = true;
      pulse.enable = true;
      alsa.enable = config.ghaf.development.debug.tools.enable;
      systemWide = false;
      extraConfig = {
        pipewire."10-remote-pulseaudio" = {
          "context.modules" = [
            {
              name = "libpipewire-module-protocol-pulse";
              args = {
                # Enable TCP socket for VMs pulseaudio clients
                "server.address" = [
                  {
                    address = "tcp:0.0.0.0:${toString cfg.guiPulseaudioTcpPort}";
                    "client.access" = "restricted";
                  }
                ];
                "pulse.min.req" = "1024/48000";
                "pulse.min.quantum" = "1024/48000";
                "pulse.idle.timeout" = "3";
              };
            }
          ];
        };
        pipewire."20-rename-tunnels" = {
          "node.rules" = [
            {
              matches = [
                { "node.name" = "~tunnel.*output*"; }
              ];
              actions = {
                update-props = {
                  "node.nick" = "audio-vm output device";
                };
              };
            }
            {
              matches = [
                { "node.name" = "~tunnel.*input*"; }
              ];
              actions = {
                update-props = {
                  "node.nick" = "audio-vm input device";
                };
              };
            }
          ];
        };
        pipewire-pulse."30-network-discover" = {
          "pulse.cmd" = [
            {
              cmd = "load-module";
              args = "module-zeroconf-discover";
              flags = [ "nofail" ];
            }
          ];
        };
      };
    };

    systemd.services =
      let
        debugLevel = if cfg.debug then "2" else "0";
      in
      {
        pipewire = {
          wantedBy = [ "multi-user.target" ];
          environment.PIPEWIRE_DEBUG = debugLevel;
        };
        pipewire-pulse = {
          wantedBy = [ "multi-user.target" ];
          serviceConfig.ExecStart = lib.mkIf (debugLevel != "0") [
            ""
            "${lib.getExe' pkgs.pipewire "pipewire-pulse"} -vvv"
          ];
        };
        wireplumber.environment.WIREPLUMBER_DEBUG = debugLevel;
      };

    ghaf = mkMerge [
      {
        # Open TCP port for the pipewire pulseaudio socket
        firewall.allowedTCPPorts = with cfg; [
          guiPulseaudioTcpPort
        ];
      }
    ];
  };
}
