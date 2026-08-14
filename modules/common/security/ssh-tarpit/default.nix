# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  config,
  lib,
  pkgs,
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
    getExe
    ;
  tarpitListenPort = 2222;
  sshPort = lib.head config.services.openssh.ports;

  waitForListenAddress = pkgs.writeShellApplication {
    name = "wait-for-ssh-tarpit-address";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.gawk
    ];
    text = ''
      addr=${lib.escapeShellArg cfg.listenAddress}
      case "$addr" in
        # Wildcard binds do not need a configured address.
        0.0.0.0 | "[::]" | ::) exit 0 ;;
      esac
      # Read /proc, not `ip`: iproute2 needs AF_NETLINK, and this check has to
      # keep working even if the unit running it is hardened. fib_trie lists
      # every locally configured address as a line ending in the address,
      # followed by "/32 host LOCAL".
      for _ in $(seq 1 60); do
        if awk -v a="$addr" '
             $NF == a { f = 1; next }
             f && /host LOCAL/ { ok = 1; exit }
             { f = 0 }
             END { exit(ok ? 0 : 1) }
           ' /proc/net/fib_trie; then
          exit 0
        fi
        sleep 1
      done
      echo "ssh-tarpit: $addr is not configured after 60s; starting anyway" >&2
    '';
  };
in
{
  _file = ./default.nix;

  options.ghaf.security.ssh-tarpit = {
    enable = mkEnableOption "SSH tarpit";
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
    # The wait lives in its own unit rather than in ssh-tarpit's ExecStartPre,
    # because ssh-tarpit is hardened to the point of being blind to the network:
    systemd.services.ssh-tarpit-wait-address = {
      description = "Wait for the ssh-tarpit listen address to be configured";
      before = [ "ssh-tarpit.service" ];
      requiredBy = [ "ssh-tarpit.service" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStart = getExe waitForListenAddress;
      };
    };

    systemd.services.ssh-tarpit = {
      description = "SSH tarpit";
      requires = [ "network.target" ];
      after = [ "ssh-tarpit-wait-address.service" ];
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        ExecStart = mkForce "${getExe pkgs.tarssh} --listen ${cfg.listenAddress}:${toString tarpitListenPort} --delay 3 --max-clients 64";
        Restart = mkForce "always";
        RestartSec = mkForce "10s";
      };
      # These two belong to [Unit], not [Service]. In serviceConfig systemd drops
      # them -- "Unknown key 'StartLimitIntervalSec' in section [Service],
      # ignoring" on every boot.
      unitConfig = {
        StartLimitBurst = mkForce 10;
        StartLimitIntervalSec = mkForce 60;
      };
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
            "-p tcp -d ${cfg.listenAddress} --dport ${toString tarpitListenPort}  -m connlimit --connlimit-upto 20 --connlimit-mask 0 -j ${config.ghaf.firewall.chainNamePrefix}conncheck-accept"
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
