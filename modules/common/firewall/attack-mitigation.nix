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
          enable = mkEnableOption "Enable SSH flood mitigation";
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
          enable = mkEnableOption "Enable Ping flood mitigation" // {
            default = true;
          };
          rule = mkOption {
            type = floodType;
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
        # Drop remaining
        iptables -I ghaf-fw-in-filter -p icmp --icmp-type echo-request -j ghaf-fw-filter-drop
        # Icmp requests
        iptables -I ghaf-fw-in-filter -p icmp --icmp-type echo-request -m hashlimit \
        --hashlimit ${toString cfg.ping.rule.maxPacketFreq} --hashlimit-burst ${toString cfg.ping.rule.burstNum} --hashlimit-mode srcip --hashlimit-name ICMP_PER_IP \
        -j ACCEPT
      '';
    };

  };
}
