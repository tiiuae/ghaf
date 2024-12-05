# Copyright 2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.ghaf.reference.programs.element-desktop;
  dendrite-pinecone = pkgs.callPackage ../../../packages/dendrite-pinecone { };
  isDendritePineconeEnabled =
    if (lib.hasAttr "services" config.ghaf.reference) then
      config.ghaf.reference.services.dendrite
    else
      false;

in
{
  options.ghaf.reference.programs.element-desktop = {
    enable = lib.mkEnableOption "element-desktop program settings";
  };
  config = lib.mkIf cfg.enable {

    systemd.services = {

      # The element-gps listens for WebSocket connections on localhost port 8000 from element-desktop
      # When a new connection is received, it executes the gpspipe program to get GPS data from GPSD and forwards it over the WebSocket
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

    networking = pkgs.lib.mkIf isDendritePineconeEnabled {
      firewall.allowedTCPPorts = [ dendrite-pinecone.TcpPortInt ];
      firewall.allowedUDPPorts = [ dendrite-pinecone.McastUdpPortInt ];
    };

  };
}
