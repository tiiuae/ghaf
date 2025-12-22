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
    mkOption
    types
    ;

in
{
  options.ghaf.services.audio = {
    hub = {
      pulseaudioTcpPort = mkOption {
        type = types.int;
        default = 4715;
        description = ''
          TCP port used by PipeWire-PulseAudio control on hub server.

          Ghaf audio clients should use this port to connect to the audio hub.
        '';
      };
      debug = mkEnableOption "debug logs for pipewire and wireplumber";
    };
  };

  config = mkIf (cfg.enable && (cfg.role == "hub")) {
    security.rtkit.enable = true;

    environment.systemPackages = with pkgs; [
      pavucontrol
    ];

    services = {
      avahi = {
        enable = true;
        ipv6 = false;
        nssmdns4 = true;
        openFirewall = true;
        allowInterfaces = [ "ethint0" ];
      };

      resolved = {
        enable = true;
        llmnr = "false";
        extraConfig = ''
          MulticastDNS=no
          DNSStubListener=yes
        '';
      };

      pipewire = {
        enable = true;
        pulse.enable = true;
        alsa.enable = config.ghaf.development.debug.tools.enable;
        systemWide = false;
        extraConfig = {
          pipewire-pulse."10-hub-server" = {
            "context.modules" = [
              {
                name = "libpipewire-module-zeroconf-discover";
                args = {
                  "pulse.discover-local" = true;
                  "pulse.latency" = 100;
                };
              }
            ];
            "pulse.properties" = {
              # the addresses this server listens on
              "server.address" = [
                "unix:native" # Run the unix native server so DE tools can connect
                #"unix:/tmp/something"              # absolute paths may be used
                #"tcp:4714"                         # IPv4 and IPv6 on all addresses
                #"tcp:[::]:9999"                    # IPv6 on all addresses
                #"tcp:127.0.0.1:8888"               # IPv4 on a single address
                #
                {
                  "address" = "tcp:${toString cfg.hub.pulseaudioTcpPort}"; # address
                  "max-clients" = 64; # maximum number of clients
                  "listen-backlog" = 32; # backlog in the server listen queue
                  "client.access" = "restricted"; # permissions for clients (restricted|unrestricted)
                }
              ];
              #server.dbus-name       = "org.pulseaudio.Server"
              "pulse.allow-module-loading" = false;
              "pulse.min.req" = "128/48000"; # 2.7ms
              "pulse.default.req" = "960/48000"; # 20 milliseconds
              "pulse.min.frag" = "128/48000"; # 2.7ms
              "pulse.default.frag" = "96000/48000"; # 2 seconds
              "pulse.default.tlength" = "96000/48000"; # 2 seconds
              "pulse.min.quantum" = "128/48000"; # 2.7ms
              #"pulse.default.format" = "F32";
              #pulse.default.position = [ FL FR ]
              "pulse.idle.timeout" = "30";
            };
            "pulse.cmd" = [
              {
                cmd = "load-module";
                args = "module-switch-on-connect";
                flags = [
                  "nofail"
                  "ignore_virtual=false"
                ];
              }
            ];
          };
          pipewire."20-add-tunnel-nicks" = {
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
        };
      };
    };

    systemd.user.services =
      let
        debugLevel = if cfg.hub.debug then "2" else "0";
      in
      {
        pipewire = {
          # Do we need to start this manually or is socket activation enough?
          wantedBy = [ "multi-user.target" ];
          environment.PIPEWIRE_DEBUG = debugLevel;
          environment.PULSE_LATENCY_MSEC = "0";
        };
        pipewire-pulse = {
          # Do we need to start this manually or is socket activation enough?
          wantedBy = [ "multi-user.target" ];
          serviceConfig.ExecStart = lib.mkIf (debugLevel != "0") [
            ""
            "${lib.getExe' pkgs.pipewire "pipewire-pulse"} -vv"
          ];
        };
        wireplumber.environment.WIREPLUMBER_DEBUG = debugLevel;
      };

    ghaf = {
      # Open TCP port for the pipewire pulseaudio socket
      firewall.allowedTCPPorts = with cfg.hub; [
        pulseaudioTcpPort
      ];
    };
  };
}
