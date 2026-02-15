# SPDX-FileCopyrightText: 2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0

# Ghaf audio server configuration
# This module should be enabled on the VM acting as the main audio server with access to all audio hardware.
# Typically, this module is enabled on the audio vm.
{
  pkgs,
  config,
  lib,
  ...
}:
let
  useGivc = config.ghaf.givc.enable;
  cfg = config.ghaf.services.audio;

in
{
  _file = ./server.nix;

  options.ghaf.services.audio = {
    server = {
      pulseaudioTcpPort = lib.mkOption {
        type = lib.types.int;
        readOnly = true;
        default = 4714;
        description = ''
          TCP port used by PipeWire-PulseAudio on the server.

          Ghaf audio hub server should use this port to connect to the audio server.
        '';
      };
      pulseaudioTcpControlPort = lib.mkOption {
        type = lib.types.int;
        readOnly = true;
        default = 4715;
        description = ''
          TCP port used by PipeWire-PulseAudio for control connections.

          Ghaf audio hub server should use this port to connect to the audio server for control operations.
        '';
      };
      pipewireForwarding = {
        enable = lib.mkEnableOption ''
          PipeWire socket forwarding to gui-vm client.

          This allows gui-vm to control audio settings via PipeWire.
          Requires givc to be enabled on both client and server.
        '';
        socket = lib.mkOption {
          type = lib.types.str;
          readOnly = true;
          default = "/tmp/pipewire-export.sock";
          description = ''
            Path to the PipeWire socket used for forwarding audio control from the server to the client.
          '';
        };
        port = lib.mkOption {
          type = lib.types.str;
          readOnly = true;
          default = "9013";
          description = ''
            TCP port used for PipeWire socket forwarding to gui-vm client.
            This port is used by the PipeWire control socket on the server.
          '';
        };
      };
      restoreOnBoot =
        lib.mkEnableOption ''
          restoring pipewire audio settings on boot from persistent storage.
        ''
        // {
          default = true;
        };
      debug = lib.mkEnableOption "debug logs for pipewire and wireplumber";
    };
  };

  config = lib.mkIf (cfg.enable && (cfg.role == "server")) (
    lib.mkMerge [
      {
        # Enable pipewire service for audioVM with pulseaudio support
        security.rtkit.enable = true;
        hardware.firmware = [ pkgs.sof-firmware ];

        services = {
          pipewire = {
            enable = true;
            pulse.enable = true;
            socketActivation = false;
            alsa.enable = config.ghaf.development.debug.tools.enable;
            systemWide = true;
            extraConfig = {
              pipewire-pulse."10-main-server" = {
                "context.modules" = [ ];
                "pulse.properties" = {
                  "server.address" = [
                    "unix:native"
                    # We don't need a unix native server on server
                    # but keep it for compatibility with CLI tools
                    {
                      "address" = "tcp:${toString cfg.server.pulseaudioTcpPort}"; # address
                      "max-clients" = 32; # maximum number of clients
                      "listen-backlog" = 32; # backlog in the server listen queue
                      "client.access" = "restricted"; # permissions for clients (restricted|unrestricted)
                    }
                    {
                      "address" = "tcp:${toString cfg.server.pulseaudioTcpControlPort}";
                      "max-clients" = 32;
                      "listen-backlog" = 32;
                      "client.access" = "unrestricted";
                    }
                  ];
                  "pulse.allow-module-loading" = false;

                  "pulse.min.req" = "128/48000"; # 2.7ms
                  "pulse.default.req" = "960/48000"; # 20 milliseconds

                  "pulse.min.frag" = "128/48000"; # 2.7ms
                  "pulse.default.frag" = "96000/48000"; # 2 seconds

                  "pulse.default.tlength" = "96000/48000"; # 2 seconds
                  "pulse.min.quantum" = "128/48000"; # 2.7ms

                  "pulse.idle.timeout" = "30";
                };
                "pulse.cmd" = [
                  {
                    # Automatically switch to newly connected devices
                    cmd = "load-module";
                    args = "module-switch-on-connect";
                    flags = [
                      "nofail"
                    ];
                  }
                ];
              };
            };
            # Disable the auto-switching to the low-quality HSP profile
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
            };
          };
        };

        systemd.services =
          let
            debugLevel = if cfg.server.debug then "2" else "0";
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
                "${lib.getExe' pkgs.pipewire "pipewire-pulse"} -vv"
              ];
            };
            wireplumber.environment.WIREPLUMBER_DEBUG = debugLevel;
          };

        ghaf = lib.mkMerge [
          {
            # Open TCP port for the pipewire pulseaudio socket
            firewall.allowedTCPPorts = with cfg.server; [
              pulseaudioTcpPort
              pulseaudioTcpControlPort
            ];
          }
          # Enable persistent storage for pipewire state to restore settings on boot
          # This is not necessarily needed as we force the server to restore at 100% volume on boot
          (lib.mkIf cfg.server.restoreOnBoot (
            lib.optionalAttrs config.ghaf.storagevm.enable {
              storagevm.directories = [
                {
                  directory = "/var/lib/pipewire";
                  user = "pipewire";
                  group = "pipewire";
                  mode = "0700";
                }
              ];
            }
          ))
        ];
      }
      # givc socket proxy is declared in modules/givc/audiovm.nix
      (lib.mkIf (cfg.server.pipewireForwarding.enable && useGivc) {
        systemd.services.pipewire-forward = {
          serviceConfig =
            let
              socketScript = pkgs.writeShellApplication {
                name = "pipewire-forward-socket";
                runtimeInputs = [ pkgs.socat ];
                text = ''
                  socat -b 65536 \
                    UNIX-LISTEN:${cfg.server.pipewireForwarding.socket},fork,reuseaddr,backlog=1024 \
                    UNIX-CONNECT:/run/pipewire/pipewire-0
                '';
              };
            in
            {
              Type = "simple";
              Restart = "on-failure";
              RestartSec = "5";
              ExecStart = "${lib.getExe socketScript}";
            };
          after = [ "pipewire.service" ];
          wantedBy = [ "multi-user.target" ];
        };
      })
    ]
  );
}
