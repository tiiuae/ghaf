# Copyright 2022-2025 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  lib,
  config,
  pkgs,
  ...
}:
let
  inherit (lib)
    mkOption
    types
    mkForce
    mkIf
    strings
    concatMapStringsSep
    optionalString
    mkBefore
    ;

  sshTcpPort = 22;
  cfg = config.ghaf.firewall;
  addIptablesRules =
    table: chain: rules:
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
      ];

      isSafe =
        rule:
        let
          tokens = strings.splitString " " rule;
        in
        builtins.all (token: !lib.elem token disallowed) tokens;

      validate =
        rule:
        if isSafe rule then
          "iptables -t ${table} -A ${chain} ${rule}"
        else
          throw "Unsafe iptables rule fragment: '${rule}' — must not contain 'iptables', -A/-I/-D, or built-in chains.";
    in
    concatMapStringsSep "\n" validate rules;

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
in
{
  options.ghaf.firewall = {

    enable = mkOption {
      type = types.bool;
      default = true;
      description = "Ghaf firewall for virtual machines";
    };
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

  };

  config = mkIf cfg.enable {

    networking.firewall = {
      enable = mkForce true;
      logRefusedConnections = true;
      rejectPackets = true;
      checkReversePath = "loose";
      logReversePathDrops = true;
      allowPing = false; # ping rule is added manually with extraCommands
      allowedTCPPorts = [ sshTcpPort ] ++ cfg.allowedTCPPorts;
      inherit (cfg) allowedUDPPorts;
      extraPackages = [
        pkgs.ipset
        pkgs.coreutils
        pkgs.gawk
      ];
      extraCommands = mkBefore ''
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


        #Create custom chain for PREROUTING
        iptables  -t mangle -N ghaf-fw-pre-mangle 2> /dev/null || true
        iptables -t mangle -I PREROUTING -j ghaf-fw-pre-mangle 2> /dev/null || true
        iptables  -t nat -N ghaf-fw-pre-nat 2> /dev/null || true
        iptables   -t nat -I PREROUTING -j ghaf-fw-pre-nat 2> /dev/null || true

        #Create custom chain for INPUT
        iptables   -t filter -N ghaf-fw-in-filter  2> /dev/null || true
        iptables  -t filter -I INPUT -j ghaf-fw-in-filter  2> /dev/null || true

        # Create custom chain for FORWARD
        iptables   -N ghaf-fw-fwd-filter 2> /dev/null || true
        iptables   -I FORWARD -j ghaf-fw-fwd-filter 2> /dev/null || true


        # Create custom chain for OUTPUT
        iptables  -t filter -N ghaf-fw-out-filter 2> /dev/null || true
        iptables  -t filter -I OUTPUT -j ghaf-fw-out-filter 2> /dev/null || true

        # Create custom chain for POSTROUTING
        iptables  -t nat -N ghaf-fw-post-nat 2> /dev/null || true
        iptables -t nat -I POSTROUTING -j ghaf-fw-post-nat 2> /dev/null || true

        # Create custom chain to add debug features for mangle tables
        iptables  -t mangle -N ghaf-fw-mangle-drop 2> /dev/null || true
        iptables  -t mangle -A ghaf-fw-mangle-drop -j DROP

        # Create custom chain to add debug features for filter tables
        iptables  -t filter -N ghaf-fw-filter-drop 2> /dev/null || true
        iptables  -t filter -A ghaf-fw-filter-drop -j DROP

        ### PREROUTING rules ###

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
        iptables -A ghaf-fw-in-filter -p icmp --icmp-type echo-request -m limit --limit 1/minute --limit-burst 5 -j ACCEPT
        iptables -A ghaf-fw-in-filter -p icmp --icmp-type echo-request -j ghaf-fw-filter-drop
        iptables -A ghaf-fw-in-filter -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT

        # nixos-fw-accept should be flushed to inject our rules
        iptables -w -F nixos-fw-accept 2> /dev/null || true
        iptables -w -A nixos-fw-accept -p tcp --syn -m conntrack --ctstate NEW -j ACCEPT
        iptables -w -A nixos-fw-accept -p udp -m conntrack --ctstate NEW  -j ACCEPT
        iptables -w -A nixos-fw-accept -j nixos-fw-log-refuse

        ### FORWARD rules ###
        iptables -t filter -A ghaf-fw-fwd-filter -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT


        ### OUTPUT rules ###
        iptables -I OUTPUT -o lo -j ACCEPT  

        ### POSTROUTING rules ###

        ### Inject the other rules ### 
        ${optionalString (cfg.extra.prerouting.mangle != [ ]) (
          addIptablesRules "mangle" "ghaf-fw-pre-mangle" cfg.extra.prerouting.mangle
        )}
        ${optionalString (cfg.extra.prerouting.nat != [ ]) (
          addIptablesRules "nat" "ghaf-fw-pre-nat" cfg.extra.prerouting.nat
        )}
        ${optionalString (cfg.extra.input.filter != [ ]) (
          addIptablesRules "filter" "ghaf-fw-in-filter" cfg.extra.input.filter
        )}
        ${optionalString (cfg.extra.forward.filter != [ ]) (
          addIptablesRules "filter" "ghaf-fw-fwd-filter" cfg.extra.forward.filter
        )}
        ${optionalString (cfg.extra.output.filter != [ ]) (
          addIptablesRules "filter" "ghaf-fw-out-filter" cfg.extra.output.filter
        )}
        ${optionalString (cfg.extra.postrouting.nat != [ ]) (
          addIptablesRules "nat" "ghaf-fw-post-nat" cfg.extra.postrouting.nat
        )}

      '';
    }
    // cfg.extraOptions;

  };
}
