# Copyright 2022-2025 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{ config, lib, ... }:

with lib;

let
  cfg = config.ghaf.firewall.attack-mitigation;
in
{
  options.ghaf.firewall.attack-mitigation = {

    enable = lib.mkEnableOption "Attack mitigation features integrated into the firewall";
    rateLimitSSH = lib.mkEnableOption "Rate-limiting to mitigate SSH syn flood attacks";
  };

  config = mkIf cfg.enable {
    # ssh syn flood protection
    ghaf.firewall.tcpBlacklistRules = mkIf cfg.rateLimitSSH [
      {
        port = lib.head config.services.openssh.ports;
        trackingSize = 100;
        burstNum = 5;
        maxPacketFreq = "30/minute"; # maximum 30 new ssh connection request/minute
      }
    ];
  };
}
