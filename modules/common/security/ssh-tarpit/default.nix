# Copyright 2022-2025 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  config,
  lib,
  ...
}:
let
  cfg = config.ghaf.security.ssh-tarpit;
  inherit (lib)
    mkIf
    mkEnableOption
    optionals
    ;
  tarpitListenPort = 2222;
  tarpitFwMarkNum = "70";
  sshPort = lib.head config.services.openssh.ports;
in
{
  options.ghaf.security.ssh-tarpit = {
    enable = mkEnableOption "Enable ssh tarpit";
    listenAddress = lib.mkOption {
      type = lib.types.str;
      default = "0.0.0.0";
      example = "[::]";
      description = ''
        Interface address to bind the ssh-tarpit daemon to SSH connections.
      '';
    };
  };

  config = mkIf cfg.enable {
    assertions = [
      {
        assertion = !(lib.elem tarpitListenPort config.services.openssh.ports);
        message = "Ssh listening ports and ssh-tarpit listening port must be different";
      }
    ];
    services.endlessh-go = {
      enable = true;
      port = tarpitListenPort;
      openFirewall = false;
      inherit (cfg) listenAddress;
      extraOptions = [ "-interval_ms 3000" ] ++ optionals config.ghaf.profiles.debug.enable [ "-v 1" ];
    };
    systemd.services.endlessh-go.serviceConfig = {
      Restart = lib.mkForce "on-failure";
      RestartSec = "10s";
      StartLimitBurst = 10;
      StartLimitIntervalSec = 60;
    };
    ghaf.firewall = {
      enable = lib.mkForce true;
      tcpBlacklistRules = [
        {
          port = sshPort;
          trackingSize = 50;
          burstNum = 5;
          maxPacketFreq = "20/minute";
          fwMarkNum = tarpitFwMarkNum;
        }
      ];
      extra = {
        prerouting = {
          nat = [
            # DNAT: incoming from banned IPs (mark ${tarpitFwMarkNum}) port 22 → honeypot:2222
            "-m mark --mark ${tarpitFwMarkNum} -p tcp --dport ${toString sshPort} -j DNAT --to-destination ${cfg.listenAddress}:${toString tarpitListenPort}"
          ];
        };
        input = {
          filter = [
            "-p tcp -d ${cfg.listenAddress} --dport ${toString tarpitListenPort}  -m connlimit --connlimit-upto 20 --connlimit-mask 0  -j ghaf-fw-conncheck-accept"
          ];
        };
        postrouting = {
          nat = [
            # MASQUERADE tarpit replies to appear from :22
            "-p tcp --sport ${toString tarpitListenPort} -j MASQUERADE --to-ports ${toString sshPort}"
          ];
        };
      };
    };
  };
}
