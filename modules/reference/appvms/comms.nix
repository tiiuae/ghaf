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
  inherit (lib) hasAttr optionals;
  dendrite-pinecone = pkgs.callPackage ../../../packages/dendrite-pinecone { };
  isDendritePineconeEnabled =
    if (hasAttr "services" config.ghaf.reference) then
      config.ghaf.reference.services.dendrite
    else
      false;
  xdgPdfPort = 1200;
in
{
  name = "${name}";

  packages =
    let
      # PDF XDG handler is executed when the user opens a PDF file in the browser
      # The xdgopenpdf script sends a command to the guivm with the file path over TCP connection
      xdgPdfItem = pkgs.makeDesktopItem {
        name = "ghaf-pdf";
        desktopName = "Ghaf PDF handler";
        exec = "${xdgOpenPdf}/bin/xdgopenpdf %u";
        mimeTypes = [ "application/pdf" ];
      };
      xdgOpenPdf = pkgs.writeShellScriptBin "xdgopenpdf" ''
        filepath=$(/run/current-system/sw/bin/realpath "$1")
        echo "Opening $filepath" | systemd-cat -p info
        echo $filepath | ${pkgs.netcat}/bin/nc -N gui-vm ${toString xdgPdfPort}
      '';
    in
    [
      pkgs.chromium
      pkgs.element-desktop
      pkgs.element-gps
      pkgs.gpsd
      pkgs.tcpdump
      pkgs.xdg-utils
      xdgPdfItem
      xdgOpenPdf
    ]
    ++ pkgs.lib.optionals isDendritePineconeEnabled [ dendrite-pinecone ];

  macAddress = "02:00:00:03:09:01";
  ramMb = 4096;
  cores = 4;
  extraModules = [
    {
      imports = [
        ../programs/chromium.nix
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
            command = "${config.ghaf.givc.appPrefix}/run-waypipe ${config.ghaf.givc.appPrefix}/chromium --enable-features=UseOzonePlatform --ozone-platform=wayland --app=https://app.slack.com/client ${config.ghaf.givc.idsExtraArgs}";
          }
        ];
      };

      ghaf.reference.programs.chromium.enable = true;

      # Set default PDF XDG handler
      xdg.mime.defaultApplications."application/pdf" = "ghaf-pdf.desktop";
    }
  ];
  borderColor = "#337aff";
  ghafAudio.enable = true;
}
