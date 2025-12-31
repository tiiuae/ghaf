# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  lib,
  config,
  pkgs,
  ...
}:
let
  inherit (lib)
    concatMapStringsSep
    mkBefore
    mkEnableOption
    mkForce
    mkIf
    mkOption
    optionals
    optionalString
    strings
    types
    mkMerge
    mkDefault
    ;
  blackListName = "BLACKLIST";
  blacklistMarkNum = "8";
  cfg = config.ghaf.firewall;

  blacklistRuleType = types.listOf (
    types.submodule {
      options = {
        port = mkOption {
          type = types.int;
          description = "Port this blacklist rule applies to.";
        };
        trackingSize = mkOption {
          type = types.int;
          description = "Maximum number of IP addresses tracking in the hashtable.";
        };
        burstNum = mkOption {
          type = types.int;
          description = "Number of packets allowed in a short time before blacklisting";
        };
        maxPacketFreq = mkOption {
          type = types.str;
          description = "Maximum average packet rate allowed from a single IP before blacklisting.";
        };
        fwMarkNum = mkOption {
          type = types.str;
          description = "Firewall mark number for blacklisted packets";
          default = blacklistMarkNum;
        };
      };
    }
  );

  addIptablesRules =
    {
      table,
      chain,
      rules,
      extraForbidden ? [ ], # default to empty list
      expected ? [ ],
    }:
    let
      disallowed = [
        "iptables"
        "-A"
        "-I"
        "-D"
        "INPUT"
        "OUTPUT"
        "FORWARD"
        "PREROUTING"
        "POSTROUTING"
      ]
      ++ extraForbidden;

      isSafe =
        rule:
        let
          tokens = strings.splitString " " rule;
        in
        # "disallowed" tokens must not be presented;however, "expected" tokens must.
        builtins.all (token: !lib.elem token disallowed) tokens;

      validate =
        rule:
        if isSafe rule then
          "iptables -t ${table} -A ${chain} ${rule}"
        else
          throw "Unsafe iptables rule fragment: '${rule}' — must not contain:  ${lib.concatStringsSep ", " disallowed},
           Expected: ${lib.concatStringsSep ", " expected}";
    in
    if rules == [ ] then "" else concatMapStringsSep "\n" validate rules;

  # Function to generate iptables commands to remove a chain hook and flush/delete the chain
  removeIptablesChain =
    chainHook: table: chainName:
    let
      deleteJumpCmd =
        if chainHook == null || chainHook == "" then
          ""
        else
          "iptables -t ${table} -D ${chainHook} -j ${chainName} 2> /dev/null || true\n";
    in
    ''
      ${deleteJumpCmd}
      iptables  -t ${table} -F ${chainName} 2> /dev/null || true
      iptables  -t ${table} -X ${chainName} 2> /dev/null || true
    '';

  appendBlacklistRule = proto: rule: chainName: ''
    iptables -t filter -A ${chainName} \
      -p ${proto} --dport ${toString rule.port} \
      -m hashlimit \
      --hashlimit-above ${rule.maxPacketFreq} \
      --hashlimit-burst ${toString rule.burstNum} \
      --hashlimit-mode srcip \
      --hashlimit-name ghaf_conn_limit_${toString rule.port} \
      --hashlimit-htable-max ${toString rule.trackingSize} \
      -j ghaf-fw-blacklist-add

     ${optionalString (rule.fwMarkNum != blacklistMarkNum) ''
       iptables -t raw -A PREROUTING \
         -m set --match-set ${blackListName} src \
         -j MARK --set-mark ${rule.fwMarkNum}
     ''}
  '';

in
{
  options.ghaf.firewall = {

    enable = mkOption {
      type = types.bool;
      default = true;
      description = "Ghaf firewall for virtual machines";
    };
    blacklistSize = mkOption {
      type = types.int;
      default = 65536;
      description = "The maximum number of IP addresses that can be stored in BLACKLIST";
    };
    tcpBlacklistRules = mkOption {
      type = blacklistRuleType;
      default = [ ];
      description = "List of blacklist settings for specific TCP ports.";
    };
    udpBlacklistRules = mkOption {
      type = blacklistRuleType;
      default = [ ];
      description = "List of blacklist settings for specific UDP ports.";
    };

    blacklistFwMarkNum = mkOption {
      type = types.str;
      readOnly = true;
      default = blacklistMarkNum;
      description = "Mark numbers for blacklisted packets.";

    };
    IdsEnabled = mkEnableOption "Ids tool";

    allowedTCPPorts = mkOption {
      type = types.listOf types.port;
      default = [ ];
      description = "Additional TCP ports to allow through the Ghaf firewall.";
    };
    allowedUDPPorts = mkOption {
      type = types.listOf types.port;
      default = [ ];
      description = "Additional UDP ports to allow through the Ghaf firewall.";
    };
    extraOptions = mkOption {
      type = types.attrsOf types.anything;
      default = { };
      description = "Extra options to extend networking.firewall configuration.";
    };
    extra = mkOption {
      type = types.submodule {
        options = {
          prerouting = mkOption {
            type = types.submodule {
              options = {
                raw = mkOption {
                  type = types.listOf types.str;
                  default = [ ];
                  description = "Extra firewall rules for raw chain";
                };
                mangle = mkOption {
                  type = types.listOf types.str;
                  default = [ ];
                  description = "Extra firewall rules for ghaf-fw-pre-mangle";
                };
                nat = mkOption {
                  type = types.listOf types.str;
                  default = [ ];
                  description = "Extra firewall rules for ghaf-fw-pre-nat";
                };

              };
            };
            default = { };
            description = "Extra firewall rules for PREROUTING chain";
          };
          input = mkOption {
            type = types.submodule {
              options = {
                filter = mkOption {
                  type = types.listOf types.str;
                  default = [ ];
                  description = "Extra firewall rules for ghaf-fw-in-filter";
                };

              };
            };
            default = { };
            description = "Extra firewall rules for INPUT chain";
          };

          forward = mkOption {
            type = types.submodule {
              options = {
                filter = mkOption {
                  type = types.listOf types.str;
                  default = [ ];
                  description = "Extra firewall rules for ghaf-fw-fwd-filter";
                };
              };
            };
            default = { };
            description = "Extra firewall rules for FORWARD chain";
          };
          output = mkOption {
            type = types.submodule {
              options = {
                filter = mkOption {
                  type = types.listOf types.str;
                  default = [ ];
                  description = "Extra firewall rules for ghaf-fw-out-filter";
                };
              };
            };
            default = { };
            description = "Extra firewall rules for OUTPUT chain";
          };
          postrouting = mkOption {
            type = types.submodule {
              options = {
                nat = mkOption {
                  type = types.listOf types.str;
                  default = [ ];
                  description = "Extra iptables rules for ghaf-fw-post-nat";
                };
              };
            };
            default = { };
            description = "Extra firewall rules for POSTROUTING chain";
          };

        };
      };
      default = { };
      description = "Extra firewall rules";
    };
    filter-arp = mkEnableOption "static ARP and MAC/IP rules";
  };

  config = mkIf cfg.enable {

    # Include required kernel modules for firewall
    ghaf.firewall.kernel-modules.enable = true;

    # Include ethertypes file
    environment.etc.ethertypes.source = "${pkgs.iptables}/etc/ethertypes";

    networking.firewall = mkMerge [
      {
        enable = mkForce true;
        logRefusedConnections = true;
        rejectPackets = mkDefault true;
        checkReversePath = mkDefault "loose";
        logReversePathDrops = mkDefault true;
        allowPing = mkDefault false;
        inherit (cfg) allowedTCPPorts;
        inherit (cfg) allowedUDPPorts;
        extraPackages = [
          pkgs.ipset
        ];
        extraCommands = mkBefore ''

          # Create BLACKLIST
          ipset create ${blackListName} hash:ip timeout 3600 maxelem ${toString cfg.blacklistSize} -exist

          # Create IDS_BLACKLIST (snort, suricata,...)
          ${lib.concatStringsSep "\n" (
            optionals cfg.IdsEnabled [
              "ipset create IDS_BLACKLIST hash:ip timeout 3600 maxelem 65536 -exist"
            ]
          )}

          # Set the default policies
          iptables  -P INPUT DROP
          iptables  -P FORWARD DROP
          iptables  -P OUTPUT ACCEPT

          # delete ctstate RELATED,ESTABLISHED and lo rules
          iptables  -D nixos-fw -i lo -j nixos-fw-accept
          iptables  -D nixos-fw -m conntrack --ctstate ESTABLISHED,RELATED -j nixos-fw-accept

          # Remove existing chain hooks and chains before recreating them
          ${removeIptablesChain "PREROUTING" "mangle" "ghaf-fw-pre-mangle"}
          ${removeIptablesChain "PREROUTING" "nat" "ghaf-fw-pre-nat"}
          ${removeIptablesChain "INPUT" "filter" "ghaf-fw-in-filter"}
          ${removeIptablesChain "FORWARD" "filter" "ghaf-fw-fwd-filter"}
          ${removeIptablesChain "OUTPUT" "filter" "ghaf-fw-out-filter"}
          ${removeIptablesChain "POSTROUTING" "nat" "ghaf-fw-post-nat"}
          ${removeIptablesChain null "filter" "ghaf-fw-filter-drop"}
          ${removeIptablesChain null "mangle" "ghaf-fw-mangle-drop"}
          ${removeIptablesChain null "filter" "ghaf-fw-conncheck-accept"}
          ${removeIptablesChain null "filter" "ghaf-fw-blacklist-add"}
          ${removeIptablesChain null "filter" "ghaf-fw-ban"}

          #Create custom chain for PREROUTING
          iptables -t mangle -N ghaf-fw-pre-mangle 2> /dev/null || true
          iptables -t mangle -I PREROUTING -j ghaf-fw-pre-mangle 2> /dev/null || true
          iptables -t nat -N ghaf-fw-pre-nat 2> /dev/null || true
          iptables -t nat -I PREROUTING -j ghaf-fw-pre-nat 2> /dev/null || true

          #Create custom chain for INPUT
          iptables -t filter -N ghaf-fw-in-filter  2> /dev/null || true
          iptables -t filter -I INPUT -j ghaf-fw-in-filter  2> /dev/null || true

          # Create custom chain for FORWARD
          iptables -N ghaf-fw-fwd-filter 2> /dev/null || true
          iptables -I FORWARD -j ghaf-fw-fwd-filter 2> /dev/null || true


          # Create custom chain for OUTPUT
          iptables -t filter -N ghaf-fw-out-filter 2> /dev/null || true
          iptables -t filter -I OUTPUT -j ghaf-fw-out-filter 2> /dev/null || true

          # Create custom chain for POSTROUTING
          iptables -t nat -N ghaf-fw-post-nat 2> /dev/null || true
          iptables -t nat -I POSTROUTING -j ghaf-fw-post-nat 2> /dev/null || true

          # Create custom chain to add debug features for mangle tables
          iptables -t mangle -N ghaf-fw-mangle-drop 2> /dev/null || true
          iptables -t mangle -A ghaf-fw-mangle-drop -j DROP

          # Create custom chain to add debug features for filter tables
          iptables -t filter -N ghaf-fw-filter-drop 2> /dev/null || true
          iptables -t filter -A ghaf-fw-filter-drop -j DROP

          # Creating custom chain to check connections for filter table
          iptables -t filter -N ghaf-fw-conncheck-accept 2> /dev/null || true


          # Creating ban list add chain
          iptables -t filter -N ghaf-fw-blacklist-add 2> /dev/null || true

          # Creating ban chain
          iptables -t filter -N ghaf-fw-ban 2> /dev/null || true

          # ghaf-fw-blacklist-add rules
          iptables -t filter -A ghaf-fw-blacklist-add -m limit --limit 10/min -j LOG --log-prefix "Blacklist [add]: " --log-level 4

          iptables -t filter -A ghaf-fw-blacklist-add -j SET --add-set ${blackListName} src --exist

          # protection if ${blackListName} is full
          iptables -t filter -A ghaf-fw-blacklist-add -j DROP

          # ghaf-fw-ban rules
          iptables -t filter -A ghaf-fw-ban -m hashlimit --hashlimit 2/min --hashlimit-burst 1 --hashlimit-mode srcip \
          --hashlimit-name log_ban_per_ip -j LOG --log-prefix "Packet [ban]: " --log-level 4

          # Everything else is dropped.
          iptables -t filter -A ghaf-fw-ban -j DROP

          ### PREROUTING rules ###
          # marking blacklisted ip packets
          iptables -t raw -A PREROUTING -m set --match-set ${blackListName} src -j MARK --set-mark ${blacklistMarkNum}
          ${addIptablesRules {
            table = "raw";
            chain = "PREROUTING";
            rules = cfg.extra.prerouting.raw;
          }}

          # Drop invalid packets
          iptables -t mangle -A ghaf-fw-pre-mangle -m conntrack --ctstate INVALID -j ghaf-fw-mangle-drop
          # Block packets with bogus TCP flags
          iptables -t mangle -A ghaf-fw-pre-mangle -p tcp --tcp-flags FIN,SYN,RST,PSH,ACK,URG NONE -j ghaf-fw-mangle-drop
          iptables -t mangle -A ghaf-fw-pre-mangle -p tcp --tcp-flags FIN,SYN FIN,SYN -j ghaf-fw-mangle-drop
          iptables -t mangle -A ghaf-fw-pre-mangle -p tcp --tcp-flags SYN,RST SYN,RST -j ghaf-fw-mangle-drop
          iptables -t mangle -A ghaf-fw-pre-mangle -p tcp --tcp-flags FIN,RST FIN,RST -j ghaf-fw-mangle-drop
          iptables -t mangle -A ghaf-fw-pre-mangle -p tcp --tcp-flags FIN,ACK FIN -j ghaf-fw-mangle-drop
          iptables -t mangle -A ghaf-fw-pre-mangle -p tcp --tcp-flags ACK,URG URG -j ghaf-fw-mangle-drop
          iptables -t mangle -A ghaf-fw-pre-mangle -p tcp --tcp-flags ACK,FIN FIN -j ghaf-fw-mangle-drop
          iptables -t mangle -A ghaf-fw-pre-mangle -p tcp --tcp-flags ACK,PSH PSH -j ghaf-fw-mangle-drop
          iptables -t mangle -A ghaf-fw-pre-mangle -p tcp --tcp-flags ALL ALL -j ghaf-fw-mangle-drop
          iptables -t mangle -A ghaf-fw-pre-mangle -p tcp --tcp-flags ALL NONE -j ghaf-fw-mangle-drop
          iptables -t mangle -A ghaf-fw-pre-mangle -p tcp --tcp-flags ALL FIN,PSH,URG -j ghaf-fw-mangle-drop
          iptables -t mangle -A ghaf-fw-pre-mangle -p tcp --tcp-flags ALL SYN,FIN,PSH,URG -j ghaf-fw-mangle-drop
          iptables -t mangle -A ghaf-fw-pre-mangle -p tcp --tcp-flags ALL SYN,RST,ACK,FIN,URG -j ghaf-fw-mangle-drop

          ### INPUT rules ###
          iptables -A ghaf-fw-in-filter -i lo -j ACCEPT
          iptables -A ghaf-fw-in-filter -m mark --mark ${blacklistMarkNum} -j ghaf-fw-ban

          iptables -A ghaf-fw-in-filter -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT

          # nixos-fw-accept should be flushed to inject our rules
          iptables -w -F nixos-fw-accept 2> /dev/null || true

          iptables -w -A nixos-fw-accept -p tcp --syn -m conntrack --ctstate NEW -j ghaf-fw-conncheck-accept
          iptables -w -A nixos-fw-accept -p udp -m conntrack --ctstate NEW  -j ghaf-fw-conncheck-accept
          ${optionalString config.networking.firewall.allowPing ''
            iptables -w -A nixos-fw-accept -p icmp -m conntrack --ctstate NEW -j ACCEPT
          ''}
          iptables -w -A nixos-fw-accept -j nixos-fw-log-refuse
          ${concatMapStringsSep "\n" (
            rule: appendBlacklistRule "tcp" rule "ghaf-fw-conncheck-accept"
          ) cfg.tcpBlacklistRules}
          ${concatMapStringsSep "\n" (
            rule: appendBlacklistRule "udp" rule "ghaf-fw-conncheck-accept"
          ) cfg.udpBlacklistRules}

          # accept the other packets
          iptables -t filter -A ghaf-fw-conncheck-accept -j ACCEPT
          ### FORWARD rules ###

          ### OUTPUT rules ###

          ### POSTROUTING rules ###

          ### Inject the other rules ###
          ${addIptablesRules {
            table = "mangle";
            chain = "ghaf-fw-pre-mangle";
            rules = cfg.extra.prerouting.mangle;
          }}
          ${addIptablesRules {
            table = "nat";
            chain = "ghaf-fw-pre-nat";
            rules = cfg.extra.prerouting.nat;
          }}
          ${addIptablesRules {
            table = "filter";
            chain = "ghaf-fw-in-filter";
            rules = cfg.extra.input.filter;
            extraForbidden = [ "ACCEPT" ];
            expected = [
              "ghaf-fw-conncheck-accept"
            ];
          }}
          ${addIptablesRules {
            table = "filter";
            chain = "ghaf-fw-fwd-filter";
            rules = cfg.extra.forward.filter;
          }}
          ${addIptablesRules {
            table = "filter";
            chain = "ghaf-fw-out-filter";
            rules = cfg.extra.output.filter;
          }}
          ${addIptablesRules {
            table = "nat";
            chain = "ghaf-fw-post-nat";
            rules = cfg.extra.postrouting.nat;
          }}

          ${optionalString (cfg.filter-arp && (lib.hasAttr "host" config.ghaf)) ''
            # Drop ARP traffic on all tap-* interfaces
            ebtables -A INPUT -p arp -j DROP -i tap-+
            ebtables -A FORWARD -p arp -j DROP -i tap-+
          ''}
        '';
      }
      cfg.extraOptions
    ];

  };
}
