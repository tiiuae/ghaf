# Copyright 2025 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.ghaf.networking.static-arp;
  inherit (lib)
    getExe
    mkIf
    mkEnableOption
    optionals
    ;

  ebtablesArpRules = pkgs.writeShellApplication {
    name = "drop-arp-traffic";
    runtimeInputs = [
      pkgs.ebtables
    ];
    text = ''
      # Drop all ARP traffic
      ebtables -A INPUT -p arp -j DROP
      ebtables -A FORWARD -p arp -j DROP
      ebtables -t broute -A BROUTING -p arp -j DROP
      ebtables -t nat -A PREROUTING -p arp -j DROP
    '';
  };
in
{
  options.ghaf.networking.static-arp = {
    enable = mkEnableOption "static ARP and MAC/IP rules";
  };

  config = mkIf cfg.enable {
    systemd.services.drop-arp = {
      description = "Configure ebtables to drop ARP traffic";
      wantedBy = [ "network.target" ];
      after = [ "network.target" ];
      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${getExe ebtablesArpRules}";
        Restart = "on-failure";
        RestartSec = "1s";
        RemainAfterExit = true;
      };
    };
    environment.systemPackages = optionals config.ghaf.profiles.debug.enable [
      pkgs.ebtables
    ];
  };
}
