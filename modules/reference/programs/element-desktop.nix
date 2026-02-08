# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.ghaf.reference.programs.element-desktop;
  inherit (lib)
    mkIf
    mkEnableOption
    ;
  isDendritePineconeEnabled =
    if (lib.hasAttr "services" config.ghaf.reference) then
      config.ghaf.reference.services.dendrite
    else
      false;

in
{
  _file = ./element-desktop.nix;

  options.ghaf.reference.programs.element-desktop = {
    enable = mkEnableOption "element-desktop program settings";
    gpsSupport = mkEnableOption "gps support for location sharing";
  };
  config = mkIf cfg.enable {

    systemd.services = {

      # The element-gps listens for WebSocket connections on localhost port 8000 from element-desktop
      # When a new connection is received, it executes the gpspipe program to get GPS data from GPSD and forwards it over the WebSocket
      element-gps = mkIf cfg.gpsSupport {
        description = "Element-gps is a GPS location provider for Element websocket interface.";
        enable = true;
        # Make sure this service is started after gpsd is running
        requires = [ "gpsd.service" ];
        after = [ "gpsd.service" ];

        serviceConfig = {
          Type = "simple";
          ExecStart = "${pkgs.gps-websock}/bin/gpswebsock";
          Restart = "on-failure";
          RestartSec = "2";
        };
        wantedBy = [ "multi-user.target" ];
      };

      "dendrite-pinecone" = mkIf isDendritePineconeEnabled {
        description = "Dendrite is a second-generation Matrix homeserver with Pinecone which is a next-generation P2P overlay network";
        enable = true;
        serviceConfig = {
          Type = "simple";
          ExecStart = "${pkgs.dendrite-pinecone}/bin/dendrite-demo-pinecone";
          Restart = "on-failure";
          RestartSec = "2";
        };
        wantedBy = [ "multi-user.target" ];
      };
    };

    ghaf.firewall = mkIf isDendritePineconeEnabled {
      allowedTCPPorts = [ pkgs.dendrite-pinecone.TcpPortInt ];
      allowedUDPPorts = [ pkgs.dendrite-pinecone.McastUdpPortInt ];
    };

  };
}
