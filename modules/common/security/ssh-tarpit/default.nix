# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
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
    mkForce
    mkOption
    types
    ;
  tarpitListenPort = 2222;
  sshPort = lib.head config.services.openssh.ports;
in
{
  _file = ./default.nix;

  options.ghaf.security.ssh-tarpit = {
    enable = mkEnableOption "Enable ssh tarpit";
    listenAddress = mkOption {
      type = types.str;
      default = "0.0.0.0";
      example = "[::]";
      description = ''
        Interface address to bind the ssh-tarpit daemon to SSH connections.
      '';
    };
    fwMarkNum = mkOption {
      type = types.str;
      default = "70";
      description = "Firewall mark number to apply to banned IPs when using iptables-ipset-mark.";
    };
  };

  config = mkIf cfg.enable {
    assertions = [
      {
        assertion = !(lib.elem tarpitListenPort config.services.openssh.ports);
        message = "Ssh listening ports and ssh-tarpit listening port must be different";
      }
      {
        assertion = config.ghaf.security.fail2ban.enable;
        message = "Fail2ban must be enabled to activate ssh-tarpit module";
      }
    ];
    services.endlessh-go = {
      enable = true;
      port = tarpitListenPort;
      openFirewall = false;
      inherit (cfg) listenAddress;
      extraOptions = [ "-interval_ms 3000 -v 1" ];
    };
    systemd.services.endlessh-go.serviceConfig = {
      Restart = lib.mkForce "on-failure";
      RestartSec = "10s";
      StartLimitBurst = 10;
      StartLimitIntervalSec = 60;
    };

    ghaf.security.fail2ban.sshd-jail-fwmark = {
      enable = mkForce true;
      fwMarkNum = mkForce "${cfg.fwMarkNum}";
    };

    ghaf.firewall = {
      enable = lib.mkForce true;
      extra = {
        prerouting = {
          nat = [
            # DNAT: incoming from banned IPs (mark ${cfg.fwMarkNum}) port 22 → honeypot:2222
            "-m mark --mark ${cfg.fwMarkNum} -p tcp --dport ${toString sshPort} -j DNAT --to-destination ${cfg.listenAddress}:${toString tarpitListenPort}"
          ];
        };
        input = {
          filter = [
            "-p tcp -d ${cfg.listenAddress} --dport ${toString tarpitListenPort}  -m connlimit --connlimit-upto 20 --connlimit-mask 0 -j ghaf-fw-conncheck-accept"
            "-m mark --mark ${cfg.fwMarkNum} -j DROP"
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
