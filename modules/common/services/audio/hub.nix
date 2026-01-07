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
      pulseLatency = mkOption {
        type = types.int;
        default = 80;
        description = ''
          Extra buffering latency in milliseconds. This controls buffering logic in `libpulse`.

          Set to 200ms by default in PipeWire's `module-pulse-tunnel`, we override to 80ms for lower latency.

          Setting this too low may cause audio dropouts or crackling.
        '';
      };
      debug = mkEnableOption "debug logs for pipewire and wireplumber";
    };
  };

  config = mkIf (cfg.enable && (cfg.role == "hub")) {
    security.rtkit.enable = true;

    environment.systemPackages = with pkgs; [
      pamixer
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
              "server.address" = [
                "unix:native" # Run the unix native server so DE tools can connect
                {
                  "address" = "tcp:${toString cfg.hub.pulseaudioTcpPort}"; # address
                  "max-clients" = 64; # maximum number of clients
                  "listen-backlog" = 32; # backlog in the server listen queue
                  "client.access" = "restricted"; # permissions for clients (restricted|unrestricted)
                }
              ];
            }
            // cfg.pulseCommonProperties;
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
        wireplumber.extraConfig = {
          disable-autoswitch = {
            "wireplumber.settings" = {
              "bluetooth.autoswitch-to-headset-profile" = "false";
            };
            "monitor.alsa.properties" = {
              "alsa.use-acp" = "true";
              "acp.auto-profile" = "true";
              "acp.auto-port" = "true";
            };
          };
          set-default-volumes = {
            "wireplumber.settings" = {
              "device.routes.default-sink-volume" = 0.4;
              "device.routes.default-source-volume" = 0.4;
            };
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

        refresh-audio-devices = {
          serviceConfig = {
            Type = "oneshot";
            ExecStart = ''${lib.getExe pkgs.bash} -c 'timeout 5s ${lib.getExe' pkgs.givc-cli "givc-cli"} ${config.ghaf.givc.cliArgs} start service --vm "audio-vm" restart-pw-pulse.service' '';
          };
        };
      };

    ghaf = {
      # Open TCP port for the pipewire pulseaudio socket
      firewall.allowedTCPPorts = with cfg.hub; [
        pulseaudioTcpPort
      ];
    };
  };
}
