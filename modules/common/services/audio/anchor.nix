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
  cfg = config.ghaf.services.audio;
  inherit (lib)
    mkEnableOption
    mkIf
    mkMerge
    mkOption
    types
    optionalAttrs
    ;

in
{
  options.ghaf.services.audio = {
    anchor = {
      pulseaudioTcpPort = mkOption {
        type = types.int;
        default = 4714;
        description = ''
          TCP port used by PipeWire-PulseAudio on the anchor server.

          Ghaf audio hub server should use this port to connect to the audio anchor server.
        '';
      };
      restoreOnBoot = mkEnableOption ''
        restoring pipewire audio settings on boot from persistent storage.

        It is recommended to keep this disabled so pipewire initializes all
        sinks and sources to 100% volume on each boot.
      '';
      debug = mkEnableOption "debug logs for pipewire and wireplumber";
    };
  };

  config = mkIf (cfg.enable && (cfg.role == "anchor")) {
    # Enable pipewire service for audioVM with pulseaudio support
    security.rtkit.enable = true;
    hardware.firmware = [ pkgs.sof-firmware ];

    services = {
      avahi = {
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
        socketActivation = false;
        alsa.enable = config.ghaf.development.debug.tools.enable;
        systemWide = true;
        extraConfig = {
          pipewire-pulse."10-anchor-server" = {
            "context.modules" = [ ];
            "pulse.properties" = {
              # the addresses this server listens on
              "server.address" = [
                #"unix:native"                # We don't need a unix native server on anchor
                #"unix:/tmp/something"        # absolute paths may be used
                #"tcp:4714"                   # IPv4 and IPv6 on all addresses
                #"tcp:[::]:9999"              # IPv6 on all addresses
                #"tcp:127.0.0.1:8888"         # IPv4 on a single address
                #
                {
                  "address" = "tcp:${toString cfg.anchor.pulseaudioTcpPort}"; # address
                  "max-clients" = 8; # maximum number of clients
                  "listen-backlog" = 32; # backlog in the server listen queue
                  "client.access" = "restricted"; # permissions for clients (restricted|unrestricted)
                }
              ];
              #"server.dbus-name"       = "org.pulseaudio.Server";
              "pulse.allow-module-loading" = false;
              "pulse.min.req" = "128/48000"; # 2.7ms
              "pulse.default.req" = "960/48000"; # 20 milliseconds
              "pulse.min.frag" = "128/48000"; # 2.7ms
              "pulse.default.frag" = "96000/48000"; # 2 seconds
              "pulse.default.tlength" = "96000/48000"; # 2 seconds
              "pulse.min.quantum" = "128/48000"; # 2.7ms
              #"pulse.default.format" = "F32";
              #"pulse.default.position" = [ FL FR ];
              "pulse.idle.timeout" = "30";
            };
            "pulse.cmd" = [
              {
                cmd = "load-module";
                args = "module-zeroconf-publish";
                flags = [ "nofail" ];
              }
            ];
          };
        };
        # Disable the auto-switching to the low-quality HSP profile
        wireplumber.extraConfig = {
          "disable-autoswitch" = {
            "wireplumber.settings" = {
              "bluetooth.autoswitch-to-headset-profile" = "false";
            };
            "monitor.alsa.properties" = {
              "alsa.use-acp" = "true";
              "acp.auto-profile" = "true";
              "acp.auto-port" = "true";
            };
          };
          "set-default-volumes" = {
            "wireplumber.settings" = {
              "device.routes.default-sink-volume" = 1.0;
              "device.routes.default-source-volume" = 1.0;
            };
          };
        };
      };
    };

    systemd.services =
      let
        debugLevel = if cfg.anchor.debug then "2" else "0";
      in
      {
        pipewire = {
          wantedBy = [ "multi-user.target" ];
          environment.PIPEWIRE_DEBUG = debugLevel;
          environment.PULSE_LATENCY_MSEC = "0";
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

    ghaf = mkMerge [
      {
        # Open TCP port for the pipewire pulseaudio socket
        firewall.allowedTCPPorts = with cfg.anchor; [
          pulseaudioTcpPort
        ];
      }
      # Enable persistent storage for pipewire state to restore settings on boot
      # This is not necessarily needed as we force the anchor to restore at 100% volume on boot
      (mkIf cfg.anchor.restoreOnBoot (
        optionalAttrs (lib.hasAttr "storagevm" config.ghaf) {
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
  };
}
