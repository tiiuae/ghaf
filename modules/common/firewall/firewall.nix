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
  rulePath = "/etc/firewall/rules/iptables.rules";
  nixosFwPrefix = "nixos-";
  ghafFwChainPrefix = cfg.chainNamePrefix;
  dynPrefix = "${ghafFwChainPrefix}dyn-";
  ipt = cfg.cmd;

  # Remove, (re)create, and optionally hook a chain. flag is "-I" or "-A".
  setupChain = hook: table: name: flag: ''
    ${removeIptablesChain hook table name}
    ${ipt} -t ${table} -N ${name} 2>/dev/null || true
    ${lib.optionalString (
      hook != null
    ) "${ipt} -t ${table} ${flag} ${hook} -j ${name} 2>/dev/null || true"}
  '';

  setupDynChain =
    table: parent: suffix:
    setupChain parent table "${dynPrefix}${table}-${suffix}" "-A";

  # Chains owned by the uplink applier. Deliberately separate from the dyn-*
  # chains, which belong to the GIVC-fed rule updater and are flushed wholesale
  # by it -- sharing them would mean each mechanism silently discarding the
  # other's rules.
  uplinkChains = [
    {
      table = "mangle";
      parent = "${ghafFwChainPrefix}pre-mangle";
      chain = "${ghafFwChainPrefix}uplink-pre-mangle";
      rules = cfg.uplink.rules.prerouting.mangle;
    }
    {
      table = "nat";
      parent = "${ghafFwChainPrefix}pre-nat";
      chain = "${ghafFwChainPrefix}uplink-pre-nat";
      rules = cfg.uplink.rules.prerouting.nat;
    }
    {
      table = "filter";
      parent = "${ghafFwChainPrefix}fwd-filter";
      chain = "${ghafFwChainPrefix}uplink-fwd-filter";
      rules = cfg.uplink.rules.forward.filter;
    }
    {
      table = "nat";
      parent = "${ghafFwChainPrefix}post-nat";
      chain = "${ghafFwChainPrefix}uplink-post-nat";
      rules = cfg.uplink.rules.postrouting.nat;
    }
  ];

  # Built through addIptablesRules so the uplink rules get exactly the same
  # eval-time validation as extra.* -- the placeholder is an ordinary token and
  # passes it. The result is executable shell with the placeholder still in it;
  # the applier substitutes and runs it.
  uplinkRuleTemplate = pkgs.writeText "ghaf-fw-uplink-rules.in" (
    lib.concatStringsSep "\n" (
      map (
        c:
        addIptablesRules {
          inherit (c) table chain rules;
        }
      ) uplinkChains
    )
  );

  uplinkFlush = lib.concatStringsSep "\n" (
    map (c: "${ipt} -t ${c.table} -F ${c.chain} 2>/dev/null || true") uplinkChains
  );

  bogusFlags =
    concatMapStringsSep "\n"
      (
        flags:
        "${ipt} -t mangle -A ${ghafFwChainPrefix}pre-mangle -p tcp --tcp-flags ${flags} -j ${ghafFwChainPrefix}mangle-drop"
      )
      [
        "FIN,SYN,RST,PSH,ACK,URG NONE"
        "FIN,SYN FIN,SYN"
        "SYN,RST SYN,RST"
        "FIN,RST FIN,RST"
        "FIN,ACK FIN"
        "ACK,URG URG"
        "ACK,FIN FIN"
        "ACK,PSH PSH"
        "ALL ALL"
        "ALL NONE"
        "ALL FIN,PSH,URG"
        "ALL SYN,FIN,PSH,URG"
        "ALL SYN,RST,ACK,FIN,URG"
      ];

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
          "${ipt} -t ${table} -A ${chain} ${rule}"
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
          "${ipt} -t ${table} -D ${chainHook} -j ${chainName} 2> /dev/null || true\n";
    in
    ''
      ${deleteJumpCmd}
      ${ipt} -t ${table} -F ${chainName} 2> /dev/null || true
      ${ipt} -t ${table} -X ${chainName} 2> /dev/null || true
    '';

  appendBlacklistRule = proto: rule: chainName: ''
    ${ipt} -t filter -A ${chainName} \
      -p ${proto} --dport ${toString rule.port} \
      -m hashlimit \
      --hashlimit-above ${rule.maxPacketFreq} \
      --hashlimit-burst ${toString rule.burstNum} \
      --hashlimit-mode srcip \
      --hashlimit-name ghaf_conn_limit_${toString rule.port} \
      --hashlimit-htable-max ${toString rule.trackingSize} \
      -j ${ghafFwChainPrefix}blacklist-add

     ${optionalString (rule.fwMarkNum != blacklistMarkNum) ''
       ${ipt} -t raw -A PREROUTING \
         -m set --match-set ${blackListName} src \
         -j MARK --set-mark ${rule.fwMarkNum}
     ''}
  '';

  applyDynamicFirewallRules = pkgs.writeShellApplication {
    name = "apply-dynamic-firewall-rules";
    runtimeInputs = with pkgs; [
      cfg.iptablesPackage
      gawk
      coreutils
      util-linux
    ];
    text = ''
      TAG="ghaf-dynamic-firewall"
      log_info() { logger -t "$TAG" -p daemon.info "$*"; }
      log_err()  { logger -t "$TAG" -p daemon.err  "$*"; }

      # Nothing to do if the rules file doesn't exist yet
      if [ ! -f "${rulePath}" ]; then
        log_info "No rules file at ${rulePath}, skipping."
        exit 0
      fi

      # Reject any rule that references reserved chain prefixes to prevent
      # tampering with ghaf or NixOS internal chains
      RESERVED=$(grep -E '(${ghafFwChainPrefix}|${nixosFwPrefix})' "${rulePath}" || true)
      if [ -n "$RESERVED" ]; then
        log_err "Rules must not reference reserved chain prefixes: $RESERVED"
        exit 1
      fi

      # Transform rules into a temp file; cleaned up on exit regardless of outcome
      TRANSFORM=$(mktemp)
      trap 'rm -f "$TRANSFORM"' EXIT

      # Rewrite built-in chain targets (INPUT, OUTPUT, ...) to their ghaf-fw-dyn-*
      # counterparts so rules land in sub-chains instead of the base firewall chains.
      # Built-in chain policy lines (:INPUT ...) and flush commands (-F INPUT) are
      # dropped — the base firewall manages those.
      awk '
        /^\*(filter|nat|mangle|raw)/ { table = substr($0, 2); print; next }
        /^COMMIT/ { print; next }
        /^-F (INPUT|OUTPUT|FORWARD|PREROUTING|POSTROUTING)( |$)/ { next }
        /^:(INPUT|OUTPUT|FORWARD|PREROUTING|POSTROUTING)( |$)/ { next }
        /^-A / {
          if ($2 ~ /^(INPUT|OUTPUT|FORWARD|PREROUTING|POSTROUTING)$/) {
            dyn = "${dynPrefix}" table "-" tolower($2)
            if (!(dyn in ok)) {
              ok[dyn] = (system("${ipt} -t " table " -L " dyn " >/dev/null 2>&1") == 0)
              if (!ok[dyn]) {
                print "ERROR: " dyn " not found in *" table > "/dev/stderr"
                exit 1
              }
            }
            $2 = dyn
          }
          print; next
        }
        { print }
      ' "${rulePath}" > "$TRANSFORM"

      # Flush all ghaf-fw-dyn-* chains before applying the new rules so stale
      # entries from the previous run don't accumulate
      for tbl in filter nat mangle raw; do
        ${ipt} -t "$tbl" -S 2>/dev/null | awk '/^-N ${dynPrefix}/ { print $2 }' | while IFS= read -r chn; do
          log_info "Flushing chain $chn (table $tbl)"
          ${ipt} -t "$tbl" -F "$chn" 2>/dev/null || true
        done
      done

      # Apply transformed rules without touching base firewall chains
      RULE_COUNT=$(grep -c '^-A' "$TRANSFORM" || true)
      log_info "Applying $RULE_COUNT dynamic firewall rules from ${rulePath}"
      iptables-restore --noflush < "$TRANSFORM"
      log_info "Dynamic firewall rules applied successfully."
    '';
  };

in
{
  _file = ./firewall.nix;

  options.ghaf.firewall = {

    enable = mkOption {
      type = types.bool;
      default = true;
      description = "Ghaf firewall for virtual machines";
    };
    chainNamePrefix = mkOption {
      type = types.str;
      default = "ghaf-fw-";
      readOnly = true;
      description = "Prefix for all ghaf firewall chain names";
    };

    uplink = {
      enable = mkEnableOption ''
        rules whose interface is only known at runtime.

        `extra.*` rules are rendered into the firewall at build time, so they
        cannot name an interface that is discovered while running -- and on
        these laptops the LAN-facing NIC is exactly that, since ethernet
        arrives as a dock or dongle. Rules placed in `uplink.rules.*` instead
        use `placeholder` where the interface goes, and are (re)applied into
        their own chains whenever the resolved uplink changes
      '';

      placeholder = mkOption {
        type = types.str;
        default = "@UPLINK@";
        description = ''
          Single token in `uplink.rules.*` replaced by the resolved interface.
          Must be one whitespace-delimited token: rule fragments are validated
          token by token.
        '';
      };

      stateFile = mkOption {
        type = types.path;
        default = "/run/ghaf-uplink-state";
        description = "Where the uplink resolver publishes the current uplink.";
      };

      readyFlag = mkOption {
        type = types.path;
        default = "/run/ghaf-uplink-ready";
        description = ''
          Gate for the apply unit. Absent means no uplink, and the rules are
          withdrawn rather than left pointing at a stale interface.
        '';
      };

      rules = mkOption {
        default = { };
        description = ''
          Same shape and same validation as `extra.*`, but applied at runtime
          with `placeholder` substituted. Only the hooks that consumers
          actually need are provided.
        '';
        type = types.submodule {
          options = {
            prerouting = mkOption {
              default = { };
              type = types.submodule {
                options = {
                  mangle = mkOption {
                    type = types.listOf types.str;
                    default = [ ];
                    description = "Uplink rules for ${ghafFwChainPrefix}uplink-pre-mangle";
                  };
                  nat = mkOption {
                    type = types.listOf types.str;
                    default = [ ];
                    description = "Uplink rules for ${ghafFwChainPrefix}uplink-pre-nat";
                  };
                };
              };
            };
            forward = mkOption {
              default = { };
              type = types.submodule {
                options = {
                  filter = mkOption {
                    type = types.listOf types.str;
                    default = [ ];
                    description = "Uplink rules for ${ghafFwChainPrefix}uplink-fwd-filter";
                  };
                };
              };
            };
            postrouting = mkOption {
              default = { };
              type = types.submodule {
                options = {
                  nat = mkOption {
                    type = types.listOf types.str;
                    default = [ ];
                    description = "Uplink rules for ${ghafFwChainPrefix}uplink-post-nat";
                  };
                };
              };
            };
          };
        };
      };
    };
    iptablesPackage = lib.mkPackageOption pkgs "iptables" { } // {
      readOnly = true;
    };
    cmd = mkOption {
      type = types.str;
      readOnly = true;
      default = "${lib.getExe cfg.iptablesPackage} -w";
      description = "iptables command used for all firewall rules (e.g. 'iptables -w' to wait for xtables lock).";
    };
    blacklistSize = mkOption {
      type = types.ints.positive; # ipset maxelem; 0 is a syntax error
      default = 65536;
      description = "The maximum number of IP addresses that can be stored in BLACKLIST";
    };
    blacklistTimeout = mkOption {
      # ipset range. 0 would mean "never expires", not "no ban".
      type = types.ints.between 1 2147483;
      default = 3600;
      description = ''
        Seconds a source IP stays in BLACKLIST once a flood rule bans it.

        Membership becomes fwmark 8 in raw PREROUTING, which ghaf-fw-in-filter
        matches ahead of the RELATED,ESTABLISHED accept, so everything addressed
        to this node is dropped including already-open connections. Forwarded
        traffic is unaffected; fwd-filter has no ban rule.

        blacklist-add re-adds with `--exist`, which resets the timer, so this
        only releases a source that goes quiet.
      '';
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
                  description = "Extra firewall rules for ${ghafFwChainPrefix}pre-mangle";
                };
                nat = mkOption {
                  type = types.listOf types.str;
                  default = [ ];
                  description = "Extra firewall rules for ${ghafFwChainPrefix}pre-nat";
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
                  description = "Extra firewall rules for ${ghafFwChainPrefix}in-filter";
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
                  description = "Extra firewall rules for ${ghafFwChainPrefix}fwd-filter";
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
                  description = "Extra firewall rules for ${ghafFwChainPrefix}out-filter";
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
                  description = "Extra iptables rules for ${ghafFwChainPrefix}post-nat";
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
    updater.enable = mkEnableOption "live update firewall rules";
  };

  config = mkIf cfg.enable {
    assertions = [
      {
        assertion = !(cfg.updater.enable && !config.ghaf.givc.policyClient.enable);
        message = "Policy Client must be enabled to update firewall rules.";
      }
    ];

    # Include required kernel modules for firewall
    ghaf.firewall.kernel-modules.enable = true;

    # Debug images: bound the outage for a source that backs off. Set here, not
    # in attack-mitigation.nix, because tcpBlacklistRules/udpBlacklistRules feed
    # BLACKLIST too -- gating on attack-mitigation.enable would leave those
    # configurations on 3600s.
    ghaf.firewall.blacklistTimeout = mkIf (config.ghaf.profiles.debug.enable or false) (mkDefault 60);

    # Include ethertypes file
    environment.etc.ethertypes.source = "${cfg.iptablesPackage}/etc/ethertypes";

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

          # Create BLACKLIST. `-exist` only tolerates an identical set, so a
          # changed timeout returns 1 and, under `sh -e`, aborts the whole
          # ruleset. `destroy` is out (raw PREROUTING references the set), but
          # `swap` works while referenced. The swap discards in-flight bans,
          # which is intended: a timeout change should not leave entries around
          # on the old expiry. The pre-emptive destroy clears any -tmp left by a
          # run that died mid-swap, which would otherwise abort the next start.
          if ! ipset create ${blackListName} hash:ip timeout ${toString cfg.blacklistTimeout} maxelem ${toString cfg.blacklistSize} -exist 2>/dev/null; then
            ipset destroy ${blackListName}-tmp 2>/dev/null || true
            ipset create ${blackListName}-tmp hash:ip timeout ${toString cfg.blacklistTimeout} maxelem ${toString cfg.blacklistSize} -exist
            ipset swap ${blackListName}-tmp ${blackListName}
            ipset destroy ${blackListName}-tmp
          fi

          # Create IDS_BLACKLIST (snort, suricata,...)
          ${lib.concatStringsSep "\n" (
            optionals cfg.IdsEnabled [
              "ipset create IDS_BLACKLIST hash:ip timeout 3600 maxelem 65536 -exist"
            ]
          )}

          # Set the default policies
          ${ipt} -P INPUT DROP
          ${ipt} -P FORWARD DROP
          ${ipt} -P OUTPUT ACCEPT

          # delete ctstate RELATED,ESTABLISHED and lo rules
          ${ipt} -D ${nixosFwPrefix}fw -i lo -j ${nixosFwPrefix}fw-accept
          ${ipt} -D ${nixosFwPrefix}fw -m conntrack --ctstate ESTABLISHED,RELATED -j ${nixosFwPrefix}fw-accept

          ${setupChain "PREROUTING" "mangle" "${ghafFwChainPrefix}pre-mangle" "-I"}
          ${setupChain "PREROUTING" "nat" "${ghafFwChainPrefix}pre-nat" "-I"}
          ${setupChain "INPUT" "filter" "${ghafFwChainPrefix}in-filter" "-I"}
          ${setupChain "FORWARD" "filter" "${ghafFwChainPrefix}fwd-filter" "-I"}
          ${setupChain "OUTPUT" "filter" "${ghafFwChainPrefix}out-filter" "-I"}
          ${setupChain "POSTROUTING" "nat" "${ghafFwChainPrefix}post-nat" "-I"}
          ${optionalString cfg.uplink.enable (
            lib.concatStringsSep "\n" (map (c: setupChain c.parent c.table c.chain "-A") uplinkChains)
          )}
          ${setupChain null "mangle" "${ghafFwChainPrefix}mangle-drop" "-I"}
          ${setupChain null "filter" "${ghafFwChainPrefix}filter-drop" "-I"}
          ${setupChain null "filter" "${ghafFwChainPrefix}conncheck-accept" "-I"}
          ${setupChain null "filter" "${ghafFwChainPrefix}blacklist-add" "-I"}
          ${setupChain null "filter" "${ghafFwChainPrefix}ban" "-I"}

          ${ipt} -t mangle -A ${ghafFwChainPrefix}mangle-drop -j DROP
          ${ipt} -t filter -A ${ghafFwChainPrefix}filter-drop -j DROP

          # ${ghafFwChainPrefix}blacklist-add rules
          # Log only if not already in blacklist
          ${ipt} -t filter -A ${ghafFwChainPrefix}blacklist-add -m set ! --match-set ${blackListName} src -m limit --limit 100/min -j LOG --log-prefix "Blacklist [add]: " --log-level 4

          ${ipt} -t filter -A ${ghafFwChainPrefix}blacklist-add -j SET --add-set ${blackListName} src --exist

          # protection if ${blackListName} is full
          ${ipt} -t filter -A ${ghafFwChainPrefix}blacklist-add -j DROP

          # ${ghafFwChainPrefix}ban rules
          ${ipt} -t filter -A ${ghafFwChainPrefix}ban -m hashlimit --hashlimit 2/min --hashlimit-burst 1 --hashlimit-mode srcip \
          --hashlimit-name log_ban_per_ip -j LOG --log-prefix "Packet [ban]: " --log-level 4

          # Everything else is dropped.
          ${ipt} -t filter -A ${ghafFwChainPrefix}ban -j DROP

          ### PREROUTING rules ###
          # Mark blacklisted IPs so the current packet is also banned immediately
          ${ipt} -t raw -A PREROUTING -m set --match-set ${blackListName} src -j MARK --set-xmark ${blacklistMarkNum}/${blacklistMarkNum}
          ${addIptablesRules {
            table = "raw";
            chain = "PREROUTING";
            rules = cfg.extra.prerouting.raw;
          }}

          # Drop invalid packets
          ${ipt} -t mangle -A ${ghafFwChainPrefix}pre-mangle -m conntrack --ctstate INVALID -j ${ghafFwChainPrefix}mangle-drop
          # Block packets with bogus TCP flags
          ${bogusFlags}

          ### INPUT rules ###
          ${ipt} -A ${ghafFwChainPrefix}in-filter -i lo -j ACCEPT
          ${ipt} -A ${ghafFwChainPrefix}in-filter -m mark --mark ${blacklistMarkNum}/${blacklistMarkNum} -j ${ghafFwChainPrefix}ban

          ${ipt} -A ${ghafFwChainPrefix}in-filter -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT

          # ${nixosFwPrefix}fw-accept should be flushed to inject our rules
          ${ipt} -F ${nixosFwPrefix}fw-accept 2> /dev/null || true

          ${ipt} -A ${nixosFwPrefix}fw-accept -p tcp --syn -m conntrack --ctstate NEW -j ${ghafFwChainPrefix}conncheck-accept
          ${ipt} -A ${nixosFwPrefix}fw-accept -p udp -m conntrack --ctstate NEW  -j ${ghafFwChainPrefix}conncheck-accept
          ${optionalString config.networking.firewall.allowPing ''
            ${ipt} -A ${nixosFwPrefix}fw-accept -p icmp -m conntrack --ctstate NEW -j ACCEPT
          ''}
          ${ipt} -A ${nixosFwPrefix}fw-accept -j ${nixosFwPrefix}fw-log-refuse
          ${concatMapStringsSep "\n" (
            rule: appendBlacklistRule "tcp" rule "${ghafFwChainPrefix}conncheck-accept"
          ) cfg.tcpBlacklistRules}
          ${concatMapStringsSep "\n" (
            rule: appendBlacklistRule "udp" rule "${ghafFwChainPrefix}conncheck-accept"
          ) cfg.udpBlacklistRules}

          # accept the other packets
          ${ipt} -t filter -A ${ghafFwChainPrefix}conncheck-accept -j ACCEPT
          ### FORWARD rules ###
          ${ipt} -t filter -A ${ghafFwChainPrefix}fwd-filter -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT

          ### OUTPUT rules ###

          ### POSTROUTING rules ###

          ### Inject the other rules ###
          ${addIptablesRules {
            table = "mangle";
            chain = "${ghafFwChainPrefix}pre-mangle";
            rules = cfg.extra.prerouting.mangle;
          }}
          ${addIptablesRules {
            table = "nat";
            chain = "${ghafFwChainPrefix}pre-nat";
            rules = cfg.extra.prerouting.nat;
          }}
          ${addIptablesRules {
            table = "filter";
            chain = "${ghafFwChainPrefix}in-filter";
            rules = cfg.extra.input.filter;
            extraForbidden = [ "ACCEPT" ];
            expected = [
              "${ghafFwChainPrefix}conncheck-accept"
            ];
          }}
          ${addIptablesRules {
            table = "filter";
            chain = "${ghafFwChainPrefix}fwd-filter";
            rules = cfg.extra.forward.filter;
          }}
          ${addIptablesRules {
            table = "filter";
            chain = "${ghafFwChainPrefix}out-filter";
            rules = cfg.extra.output.filter;
          }}
          ${addIptablesRules {
            table = "nat";
            chain = "${ghafFwChainPrefix}post-nat";
            rules = cfg.extra.postrouting.nat;
          }}

          ${optionalString (cfg.filter-arp && (lib.hasAttr "host" config.ghaf)) ''
            # Drop ARP traffic on all tap-* interfaces
            ebtables -A INPUT -p arp -j DROP -i tap-+
            ebtables -A FORWARD -p arp -j DROP -i tap-+
          ''}

        '';
      }
      (mkIf cfg.updater.enable {
        # Create dedicated dynamic chains jumped from the extension chains.
        # Only these ${dynPrefix}* chains are flushed and reloaded on live updates,
        # keeping all core chains (${ghafFwChainPrefix}ban, ${ghafFwChainPrefix}conncheck-accept, etc.) intact.
        extraCommands = ''
          ${setupDynChain "filter" "${ghafFwChainPrefix}in-filter" "input"}
          ${setupDynChain "filter" "${ghafFwChainPrefix}fwd-filter" "forward"}
          ${setupDynChain "filter" "${ghafFwChainPrefix}out-filter" "output"}
          ${setupDynChain "mangle" "${ghafFwChainPrefix}pre-mangle" "prerouting"}
          ${setupDynChain "nat" "${ghafFwChainPrefix}pre-nat" "prerouting"}
          ${setupDynChain "nat" "${ghafFwChainPrefix}post-nat" "postrouting"}
        '';
      })
      cfg.extraOptions
    ];

    networking.nat =
      let
        natCfg = config.networking.nat;
        ifaceFlag = lib.optionalString (natCfg.externalInterface != null) "-o ${natCfg.externalInterface}";
        destFlag =
          if natCfg.externalIP != null then "-j SNAT --to-source ${natCfg.externalIP}" else "-j MASQUERADE";
        natErr = msg: ''{ echo "ERROR: firewall.nix: ${msg} — review networking.nat patch" >&2; exit 1; }'';
      in
      mkMerge [
        {
          extraCommands = mkBefore ''
            # Replace NixOS nat MARK set (overwrite) with --set-xmark (OR) so that
            # marks set in raw PREROUTING are preserved through nat PREROUTING.
            # Use bitmask match so it still applies when other mark bits are set.
            ${lib.concatMapStringsSep "\n" (iface: ''
              ${ipt} -t nat -D ${nixosFwPrefix}nat-pre -i ${iface} -j MARK --set-mark 1 \
                || ${natErr "${nixosFwPrefix}nat-pre mark rule not found for ${iface}"}
              ${ipt} -t nat -A ${nixosFwPrefix}nat-pre -i ${iface} -j MARK --set-xmark 0x1/0x1
            '') natCfg.internalInterfaces}
            ${lib.optionalString (natCfg.internalInterfaces != [ ]) ''
              ${ipt} -t nat -D ${nixosFwPrefix}nat-post -m mark --mark 1 ${ifaceFlag} ${destFlag} \
                || ${natErr "${nixosFwPrefix}nat-post mark rule not found"}
              ${ipt} -t nat -A ${nixosFwPrefix}nat-post -m mark --mark 0x1/0x1 ${ifaceFlag} ${destFlag}
            ''}
          '';
        }
      ];

    ghaf.givc.policyClient.policies = mkIf cfg.updater.enable {
      firewall-rules = {
        dest = rulePath;
        updater = {
          url = "https://raw.githubusercontent.com/tiiuae/ghaf-policies/deploy/vm-policies/firewall-rules/iptables.rules";
          poll_interval_secs = 300;
        };
      };
    };
    systemd = lib.mkMerge [
      (mkIf cfg.uplink.enable {
        services.ghaf-firewall-uplink = {
          description = "Apply firewall rules for the resolved uplink interface";
          wantedBy = [
            "multi-user.target"
            "firewall.service"
          ];
          after = [
            "firewall.service"
            "ghaf-uplink-resolver.service"
          ];
          # firewall.service recreates and flushes the ghaf chains, so the rules
          # have to be reapplied after it restarts, not just after the uplink moves.
          partOf = [ "firewall.service" ];

          # No uplink => this unit is skipped and the chains stay empty, which is
          # the correct posture: rules naming a stale interface would either match
          # nothing or, worse, match the wrong one. Skipped is visible in
          # `systemctl status`; it is neither a spurious failure nor a silent
          # success.
          unitConfig = {
            ConditionPathExists = cfg.uplink.readyFlag;
            # Same reasoning as the resolver: this is restarted whenever the
            # uplink moves, and being rate-limited out of running would leave
            # the chains holding rules for an interface that is gone. Stale
            # firewall rules are a worse outcome than restart churn.
            StartLimitIntervalSec = 0;
          };

          serviceConfig = {
            Type = "oneshot";
            RemainAfterExit = true;
            ExecStart = lib.getExe (
              pkgs.writeShellApplication {
                name = "ghaf-firewall-uplink-apply";
                runtimeInputs = [
                  cfg.iptablesPackage
                  pkgs.gnused
                  pkgs.coreutils
                ];
                text = ''
                  # shellcheck disable=SC1091
                  . ${cfg.uplink.stateFile}
                  if [ -z "''${uplink_iface:-}" ]; then
                    echo "ghaf-firewall-uplink: ${cfg.uplink.stateFile} names no uplink; leaving the chains empty." >&2
                    exit 1
                  fi
                  ${uplinkFlush}
                  sed -e "s|${cfg.uplink.placeholder}|$uplink_iface|g" ${uplinkRuleTemplate} >/run/ghaf-fw-uplink-rules
                  # The template is generated by addIptablesRules at build time, so
                  # it is the same validated shell those rules would have been had
                  # they been static -- only the interface is late-bound.
                  # shellcheck disable=SC1091
                  . /run/ghaf-fw-uplink-rules
                  echo "ghaf-firewall-uplink: applied uplink rules on $uplink_iface"
                '';
              }
            );
            # Withdraw the rules when the unit stops, so they can never outlive the
            # interface they were written for.
            ExecStop = lib.getExe (
              pkgs.writeShellApplication {
                name = "ghaf-firewall-uplink-clear";
                runtimeInputs = [ cfg.iptablesPackage ];
                text = ''
                  ${uplinkFlush}
                  echo "ghaf-firewall-uplink: cleared uplink rules"
                '';
              }
            );
          };
        };
      })

      (mkIf cfg.updater.enable {
        paths.apply-dynamic-firewall-rules = {
          description = "Watch dynamic firewall rules file for changes";
          wantedBy = [ "multi-user.target" ];
          pathConfig.PathModified = rulePath;
        };

        services.apply-dynamic-firewall-rules = {
          description = "Apply dynamic firewall rules";
          wantedBy = [
            "multi-user.target"
            "firewall.service"
          ];
          after = [ "firewall.service" ];
          serviceConfig = {
            Type = "oneshot";
            ExecStart = lib.getExe applyDynamicFirewallRules;
          };
        };
      })
    ];
  };
}
