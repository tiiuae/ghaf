# Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
{
  pkgs,
  config,
  ...
}: let
  dendrite-pinecone = pkgs.callPackage ../../../packages/dendrite-pinecone {};
  isDendritePineconeEnabled = config.ghaf.services.dendrite-pinecone.enable;
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
      sound.enable = true;
      hardware.pulseaudio.enable = true;
      users.extraUsers.ghaf.extraGroups = ["audio" "video"];

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

        network = {
          enable = true;
          networks."10-ethint0" = {
            DHCP = pkgs.lib.mkForce "no";
            matchConfig.Name = "ethint0";
            addresses = [
              {
                addressConfig.Address = "192.168.100.253/24";
              }
            ];
            routes = [{routeConfig.Gateway = "192.168.100.1";}];
            linkConfig.RequiredForOnline = "routable";
            linkConfig.ActivationPolicy = "always-up";
          };
        };
      };

      networking = pkgs.lib.mkIf isDendritePineconeEnabled {
        firewall.allowedTCPPorts = [dendrite-pinecone.TcpPortInt];
        firewall.allowedUDPPorts = [dendrite-pinecone.McastUdpPortInt];
      };

      time.timeZone = "${config.time.timeZone}";

      services.gpsd = {
        enable = true;
        devices = ["/dev/ttyUSB0"];
        readonly = true;
        debugLevel = 2;
        listenany = true;
        extraArgs = ["-n"]; # Do not wait for a client to connect before polling
      };

      microvm.qemu.extraArgs = [
        # Note: If you want to enable integrated camera in element-vm,
        # remove enabling camera line from chromium-vm
        # Lenovo X1 integrated usb webcam
        "-device"
        "qemu-xhci"
        "-device"
        "usb-host,hostbus=3,hostport=8"
        # Connect sound device to hosts pulseaudio socket
        "-audiodev"
        "pa,id=pa1,server=unix:/run/pulse/native"
        # Add HDA sound device to guest
        "-device"
        "intel-hda"
        "-device"
        "hda-duplex,audiodev=pa1"
        # External USB GPS receiver
        "-device"
        "usb-host,vendorid=0x067b,productid=0x23a3"
      ];
    }
  ];
  borderColor = "#337aff";
}
