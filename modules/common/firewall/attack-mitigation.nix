# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{ config, lib, ... }:
let
  cfg = config.ghaf.firewall.attack-mitigation;

  inherit (lib)
    mkOption
    mkEnableOption
    mkAfter
    mkForce
    mkIf
    types
    ;

  floodType = types.submodule {
    options = {
      burstNum = mkOption {
        type = types.int;
        description = "Number of packets allowed in a short time before blacklisting";
      };
      maxPacketFreq = mkOption {
        type = types.str;
        description = "Maximum average packet rate allowed from a single IP before blacklisting.";
      };
    };
  };
in
{
  _file = ./attack-mitigation.nix;

  options.ghaf.firewall.attack-mitigation = {

    enable = mkEnableOption "Attack mitigation features integrated into the firewall" // {
      default = true;
    };

    # SSH flood mitigation options
    ssh = mkOption {
      type = types.submodule {
        options = {
          enable = mkEnableOption "SSH flood mitigation";
          rule = mkOption {
            type = floodType;
            default = {
              burstNum = 5;
              maxPacketFreq = "30/minute";
            };
            description = "Flood rule parameters for SSH";
          };
        };
      };
      default = {
        enable = false;
        rule = {
          burstNum = 5;
          maxPacketFreq = "30/minute";
        };
      };
      description = "SSH flood mitigation settings";
    };

    # Ping (icmp) flood mitigation options
    ping = mkOption {
      type = types.submodule {
        options = {
          enable = mkEnableOption "Ping flood mitigation" // {
            default = true;
          };
          rule = mkOption {
            type = floodType;
            # Load-bearing: any definition of `ping.rule`, even behind a false
            # mkIf, suppresses the aggregate `ping` default below and would
            # leave burstNum/maxPacketFreq unset. `ssh.rule` does the same.
            default = {
              burstNum = 10;
              maxPacketFreq = "60/min";
            };
            description = "Flood rule parameters for Ping";
          };
        };
      };
      default = {
        enable = true;
        rule = {
          burstNum = 10;
          maxPacketFreq = "60/min";
        };
      };
      description = "Ping flood mitigation settings";
    };
  };

  config = mkIf cfg.enable {
    assertions = [
      {
        assertion =
          !(lib.hasAttr "allowPing" config.ghaf.firewall.extraOptions)
          ||
            config.ghaf.firewall.extraOptions.allowPing != config.ghaf.firewall.attack-mitigation.ping.enable;
        message = "ghaf.firewall.extraOptions.allowPing and ghaf.firewall.attack-mitigation.ping.enable cannot be set at the same time";
      }
    ];
    # Debug images: relax both limiters, which ban via BLACKLIST (see
    # blacklistTimeout in firewall.nix). Same debug gate as security/fail2ban.nix.
    #
    # Production ping is `above 1/sec burst 10`: `ping -i0.2` from ghaf-host
    # blacklisted it on net-vm and killed the host<->net-vm link, while every tap
    # and bridge counter read zero drops -- invisible at L2, so it looks like a
    # virtio fault rather than a firewall action.
    ghaf.firewall.attack-mitigation.ping.rule = mkIf (config.ghaf.profiles.debug.enable or false) (
      lib.mkDefault {
        burstNum = 100;
        maxPacketFreq = "3600/minute";
      }
    );

    # Production ssh is burst 5 / 30-per-minute of NEW connections per source
    # (ESTABLISHED is accepted earlier, so it counts logins not packets): ~six
    # quick logins, and a dev jumping through net-vm spends two per command.
    ghaf.firewall.attack-mitigation.ssh.rule = mkIf (config.ghaf.profiles.debug.enable or false) (
      lib.mkDefault {
        burstNum = 100;
        maxPacketFreq = "1000/minute";
      }
    );

    # ssh syn flood protection
    ghaf.firewall.tcpBlacklistRules = mkIf cfg.ssh.enable [
      {
        port = builtins.head config.services.openssh.ports;
        trackingSize = 100;
        inherit (cfg.ssh.rule) burstNum;
        inherit (cfg.ssh.rule) maxPacketFreq;
      }
    ];
    # ping flood protection
    ghaf.firewall.extraOptions = mkIf cfg.ping.enable {
      allowPing = mkForce false;
      extraCommands = mkAfter ''
         # Accept normal ICMP requests (only if not blacklisted)
        ${config.ghaf.firewall.cmd} -I ${config.ghaf.firewall.chainNamePrefix}in-filter -p icmp --icmp-type echo-request -m mark ! --mark ${config.ghaf.firewall.blacklistFwMarkNum} -j ACCEPT
         # Blacklist when rate exceeded
        ${config.ghaf.firewall.cmd} -I ${config.ghaf.firewall.chainNamePrefix}in-filter -p icmp --icmp-type echo-request \
          -m hashlimit \
          --hashlimit-above ${toString cfg.ping.rule.maxPacketFreq} \
          --hashlimit-burst ${toString cfg.ping.rule.burstNum} \
          --hashlimit-mode srcip \
          --hashlimit-name ICMP_PER_IP \
          -j ${config.ghaf.firewall.chainNamePrefix}blacklist-add
      '';
    };

  };
}
