# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.ghaf.security.fail2ban;
  inherit (lib)
    mkIf
    mkEnableOption
    types
    mkOption
    ;
in
{
  _file = ./fail2ban.nix;

  options.ghaf.security.fail2ban = {
    enable = mkEnableOption "the fail2ban";
    sshd-jail-fwmark = mkOption {
      type = types.submodule {
        options = {
          enable = mkEnableOption "sshd custom jail";
          fwMarkNum = mkOption {
            type = types.str;
            default = "70";
            description = "Firewall mark number to apply to banned IPs when using iptables-ipset-mark.";
          };
          blacklistName = mkOption {
            type = types.strMatching "^[a-zA-Z]{1,31}$";
            default = "sshBlacklist";
            description = ''
              Blacklist name for fail2ban
            '';
          };
        };
      };
      default = { };
      description = "Configuration for the SSHD Fail2Ban jail using firewall marks.";

    };

  };

  config = mkIf cfg.enable {
    services.fail2ban = {
      enable = true;
      extraPackages = [ pkgs.ipset ];
      bantime = "30m";
      maxretry = if (config.ghaf.profiles.debug.enable or false) then 10 else 3;
      bantime-increment.enable = true;
      bantime-increment.factor = "2";
      jails = {
        # sshd is jailed by default
        sshd.settings = {
          enabled = true;
          banaction =
            if cfg.sshd-jail-fwmark.enable then
              "iptables-ipset-mark"
            else
              "iptables-ipset-proto6-allports[name=${cfg.sshd-jail-fwmark.blacklistName},blocktype=DROP]";
        };

      };
    };

    # Only provide custom action file if user selects iptables-ipset-mark
    environment.etc = mkIf cfg.sshd-jail-fwmark.enable {
      "fail2ban/action.d/iptables-ipset-mark.conf".text = ''
        [INCLUDES]
        before = iptables-ipset-proto6-allports.conf

        [Definition]
        rule-jump = -m set --match-set <ipmset> src -j MARK --set-mark ${cfg.sshd-jail-fwmark.fwMarkNum}

        [Init]
        chain = PREROUTING
        ipmset = f2b-${cfg.sshd-jail-fwmark.blacklistName}
        iptables = iptables -t raw <lockingopt>

      '';
    };

  };
}
