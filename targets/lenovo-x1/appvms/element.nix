# Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
{pkgs, ...}: let
  dendriteTcpPort = 49000;
  dendriteUdpPort = 60606;
  dendrite-pinecone = pkgs.callPackage ../../../packages/dendrite-pinecone {};
in {
  name = "element";

  packages = [dendrite-pinecone pkgs.tcpdump pkgs.element-desktop];
  macAddress = "02:00:00:03:08:01";
  ramMb = 3072;
  cores = 4;
  extraModules = [
    {
      systemd.network = {
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

      networking = {
        firewall.allowedTCPPorts = [dendriteTcpPort];
        firewall.allowedUDPPorts = [dendriteUdpPort];
      };

      time.timeZone = "Asia/Dubai";

      systemd.services."dendrite-pinecone" = {
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
    }
  ];
  borderColor = "#337aff";
}
