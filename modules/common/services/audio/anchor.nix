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
      authIpAcl = mkOption {
        description = ''
          IP ACL for clients allowed to connect to the PipeWire-Pulse TCP socket.

          By default, allow only gui-vm to connect, as it's the default hub server.

          Set to an empty string to allow all VMs (not recommended).
        '';
        type = types.nullOr types.str;
        defaultText = "config.ghaf.networking.hosts.gui-vm.ipv4";
        default = config.ghaf.networking.hosts."gui-vm".ipv4;
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
        alsa.enable = config.ghaf.development.debug.tools.enable;
        systemWide = true;
        extraConfig = {
          pipewire-pulse."10-pulse-config" = {
            "pulse.properties" = {
              "pulse.min.req" = "128/48000";
              "pulse.min.quantum" = "128/48000";
              "pulse.idle.timeout" = "0";
            };
          };
          pipewire-pulse."20-network-publish" = {
            "pulse.cmd" = [
              {
                cmd = "load-module";
                args = "module-zeroconf-publish";
                flags = [ "nofail" ];
              }
              {
                cmd = "load-module";
                args = "module-native-protocol-tcp listen=0.0.0.0 port=${toString cfg.anchor.pulseaudioTcpPort} auth-ip-acl=${
                  if (cfg.anchor.authIpAcl == "" || cfg.anchor.authIpAcl == null) then
                    "192.168.100.0/8"
                  else
                    cfg.anchor.authIpAcl
                }";
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
      # This is not necessarily needed as we
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
