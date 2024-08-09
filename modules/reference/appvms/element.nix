# Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
{
  pkgs,
  lib,
  config,
  ...
}: let
  inherit (lib) hasAttr optionals;
  dendrite-pinecone = pkgs.callPackage ../../../packages/dendrite-pinecone {};
  isDendritePineconeEnabled =
    if (hasAttr "services" config.ghaf.reference)
    then config.ghaf.reference.services.dendrite
    else false;
in {
  name = "element";

  packages =
    [
      pkgs.element-desktop
      pkgs.element-gps
      pkgs.gpsd
      pkgs.tcpdump
      pkgs.pulseaudio
    ]
    ++ pkgs.lib.optionals isDendritePineconeEnabled [dendrite-pinecone];
  macAddress = "02:00:00:03:09:01";
  ramMb = 4096;
  cores = 4;
  extraModules = [
    {
      # Enable pulseaudio for user ghaf to access mic
      security.rtkit.enable = true;
      users.extraUsers.ghaf.extraGroups = ["audio" "video"];

      hardware.pulseaudio = {
        enable = true;
        extraConfig = ''
          load-module module-tunnel-sink sink_name=element-speaker server=audio-vm:4713 format=s16le channels=2 rate=48000
          load-module module-tunnel-source source_name=element-mic server=audio-vm:4713 format=s16le channels=1 rate=48000

          # Set sink and source default max volume to about 90% (0-65536)
          set-sink-volume element-speaker 60000
          set-source-volume element-mic 60000
        '';
      };

      systemd = {
        services = {
          element-gps = {
            description = "Element-gps is a GPS location provider for Element websocket interface.";
            enable = true;
            serviceConfig = {
              Type = "simple";
              ExecStart = "${pkgs.element-gps}/bin/main.py";
              Restart = "on-failure";
              RestartSec = "2";
            };
            wantedBy = ["multi-user.target"];
          };

          "dendrite-pinecone" = pkgs.lib.mkIf isDendritePineconeEnabled {
            description = "Dendrite is a second-generation Matrix homeserver with Pinecone which is a next-generation P2P overlay network";
            enable = true;
            serviceConfig = {
              Type = "simple";
              ExecStart = "${dendrite-pinecone}/bin/dendrite-demo-pinecone";
              Restart = "on-failure";
              RestartSec = "2";
            };
            wantedBy = ["multi-user.target"];
          };
        };
      };

      networking = pkgs.lib.mkIf isDendritePineconeEnabled {
        firewall.allowedTCPPorts = [dendrite-pinecone.TcpPortInt];
        firewall.allowedUDPPorts = [dendrite-pinecone.McastUdpPortInt];
      };

      time.timeZone = config.time.timeZone;

      services.gpsd = {
        enable = true;
        devices = ["/dev/ttyUSB0"];
        readonly = true;
        debugLevel = 2;
        listenany = true;
        extraArgs = ["-n"]; # Do not wait for a client to connect before polling
      };

      microvm.qemu.extraArgs = optionals (config.ghaf.hardware.usb.external.enable
        && (hasAttr "gps0" config.ghaf.hardware.usb.external.qemuExtraArgs))
      config.ghaf.hardware.usb.external.qemuExtraArgs.gps0;
    }
  ];
  borderColor = "#337aff";
}
