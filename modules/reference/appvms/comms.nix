# Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
{
  lib,
  pkgs,
  config,
  ...
}:
let
  name = "comms";
  hostsEntries = import ../../common/networking/hosts-entries.nix;
  vmname = name + "-vm";
  inherit (lib) hasAttr optionals;
  dendrite-pinecone = pkgs.callPackage ../../../packages/dendrite-pinecone { };
  isDendritePineconeEnabled =
    if (hasAttr "services" config.ghaf.reference) then
      config.ghaf.reference.services.dendrite
    else
      false;
in
{
  name = "${name}";

  packages = [
    pkgs.google-chrome
    pkgs.element-desktop
    pkgs.element-gps
    pkgs.gpsd
    pkgs.tcpdump
  ] ++ pkgs.lib.optionals isDendritePineconeEnabled [ dendrite-pinecone ];
  macAddress = "02:00:00:03:09:01";
  internalIP = hostsEntries.ipByName vmname;

  ramMb = 4096;
  cores = 4;
  extraModules = [
    {
      imports = [
        # ../programs/chromium.nix
        ../programs/google-chrome.nix

      ];

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
            wantedBy = [ "multi-user.target" ];
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
            wantedBy = [ "multi-user.target" ];
          };
        };
      };

      networking = pkgs.lib.mkIf isDendritePineconeEnabled {
        firewall.allowedTCPPorts = [ dendrite-pinecone.TcpPortInt ];
        firewall.allowedUDPPorts = [ dendrite-pinecone.McastUdpPortInt ];
      };

      time.timeZone = config.time.timeZone;

      services.gpsd = {
        enable = true;
        devices = [ "/dev/ttyUSB0" ];
        readonly = true;
        debugLevel = 2;
        listenany = true;
        extraArgs = [ "-n" ]; # Do not wait for a client to connect before polling
      };

      microvm.qemu.extraArgs = optionals (
        config.ghaf.hardware.usb.external.enable
        && (hasAttr "gps0" config.ghaf.hardware.usb.external.qemuExtraArgs)
      ) config.ghaf.hardware.usb.external.qemuExtraArgs.gps0;

      ghaf.givc.appvm = {
        enable = true;
        name = lib.mkForce "${name}-vm";
        applications = [
          {
            name = "element";
            command = "${config.ghaf.givc.appPrefix}/run-waypipe ${config.ghaf.givc.appPrefix}/element-desktop --enable-features=UseOzonePlatform --ozone-platform=wayland";
          }
          {
            name = "slack";
            command = "${config.ghaf.givc.appPrefix}/run-waypipe ${config.ghaf.givc.appPrefix}/google-chrome-stable --enable-features=UseOzonePlatform --ozone-platform=wayland --app=https://app.slack.com/client ${config.ghaf.givc.idsExtraArgs}";
          }
          {
            name = "zoom";
            command = "${config.ghaf.givc.appPrefix}/run-waypipe ${config.ghaf.givc.appPrefix}/google-chrome-stable --enable-features=UseOzonePlatform --ozone-platform=wayland --app=https://app.zoom.us/wc/home ${config.ghaf.givc.idsExtraArgs}";
          }
        ];
      };
      ghaf.reference.programs.google-chrome.enable = true;
      ghaf.services.xdghandlers.enable = true;
    }
  ];
  borderColor = "#337aff";
  ghafAudio.enable = true;
}
