# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
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
    ;
in
{
  options.ghaf.services.audio = {
    enable = mkEnableOption "Enable audio service for audio VM";
    debug = mkOption {
      type = types.bool;
      default = false;
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
      systemWide = true;
      extraConfig = {
        pipewire-pulse."10-network-publish" = {
          "pulse.cmd" = [
            {
              cmd = "load-module";
              args = "module-zeroconf-publish";
              flags = [ "nofail" ];
            }
            {
              cmd = "load-module";
              args = "module-native-protocol-tcp listen=0.0.0.0 port=${toString cfg.pulseaudioTcpControlPort} auth-ip-acl=192.168.100.0/8";
              flags = [ "nofail" ];
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
          pulseaudioTcpPort
          pulseaudioTcpControlPort
        ];
      }
      # Enable persistent storage for pipewire state to restore settings on boot
      (optionalAttrs (lib.hasAttr "storagevm" config.ghaf) {
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
