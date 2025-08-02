# Copyright 2022-2025 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  lib,
  config,
  pkgs,
  ...
}:
let

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
          tokens = lib.strings.splitString " " rule;
        in
        builtins.all (token: !lib.elem token disallowed) tokens;

      validate =
        rule:
        if isSafe rule then
          "iptables -w -t ${table} -A ${chain} ${rule}"
        else
          throw "Unsafe iptables rule fragment: '${rule}' — must not contain 'iptables', -A/-I/-D, or built-in chains.";
    in
    lib.concatMapStringsSep "\n" validate rules;

  # Function to generate iptables commands to remove a chain hook and flush/delete the chain
  removeIptablesChain =
    chainHook: table: chainName:
    let
      deleteJumpCmd =
        if chainHook == null || chainHook == "" then
          ""
        else
          "iptables -w -t ${table} -D ${chainHook} -j ${chainName} 2> /dev/null || true\n";
    in
    ''
      ${deleteJumpCmd}
      iptables -w -t ${table} -F ${chainName} 2> /dev/null || true
      iptables -w -t ${table} -X ${chainName} 2> /dev/null || true
    '';
in
{
  options.ghaf.firewall = {

    enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Ghaf firewall for virtual machines";
    };
    allowedTCPPorts = lib.mkOption {
      type = lib.types.listOf lib.types.port;
      default = [ ];
      description = "Additional TCP ports to allow through the Ghaf firewall.";
    };
    allowedUDPPorts = lib.mkOption {
      type = lib.types.listOf lib.types.port;
      default = [ ];
      description = "Additional TCP ports to allow through the Ghaf firewall.";
    };
    extraOptions = lib.mkOption {
      type = lib.types.attrsOf lib.types.anything;
      default = { };
      description = "Extra options to extend networking.firewall configuration.";
    };
    extra = lib.mkOption {
      type = lib.types.submodule {
        options = {
          prerouting = lib.mkOption {
            type = lib.types.submodule {
              options = {
                mangle = lib.mkOption {
                  type = lib.types.listOf lib.types.str;
                  default = [ ];
                  description = "Extra firewall rules for ghaf-fw-pre-mangle";
                };
                nat = lib.mkOption {
                  type = lib.types.listOf lib.types.str;
                  default = [ ];
                  description = "Extra firewall rules for ghaf-fw-pre-nat";
                };

              };
            };
            default = { };
            description = "Extra firewall rules for PREROUTING chain";
          };
          input = lib.mkOption {
            type = lib.types.submodule {
              options = {
                filter = lib.mkOption {
                  type = lib.types.listOf lib.types.str;
                  default = [ ];
                  description = "Extra firewall rules for ghaf-fw-in-filter";
                };

              };
            };
            default = { };
            description = "Extra firewall rules for INPUT chain";
          };

          forward = lib.mkOption {
            type = lib.types.submodule {
              options = {
                filter = lib.mkOption {
                  type = lib.types.listOf lib.types.str;
                  default = [ ];
                  description = "Extra firewall rules for ghaf-fw-fwd-filter";
                };
              };
            };
            default = { };
            description = "Extra firewall rules for FORWARD chain";
          };
          output = lib.mkOption {
            type = lib.types.submodule {
              options = {
                filter = lib.mkOption {
                  type = lib.types.listOf lib.types.str;
                  default = [ ];
                  description = "Extra firewall rules for ghaf-fw-out-filter";
                };
              };
            };
            default = { };
            description = "Extra firewall rules for OUTPUT chain";
          };
          postrouting = lib.mkOption {
            type = lib.types.submodule {
              options = {
                nat = lib.mkOption {
                  type = lib.types.listOf lib.types.str;
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

  config = lib.mkIf cfg.enable {

    networking.firewall = {
      enable = lib.mkForce true;
      logRefusedConnections = true;
      rejectPackets = true;
      checkReversePath = "loose";
      logReversePathDrops = true;
      allowPing = false; # ping rule is added manually with extraCommands
      allowedTCPPorts = [ 22 ] ++ cfg.allowedTCPPorts;
      allowedUDPPorts = [ 67 ] ++ cfg.allowedUDPPorts;
      extraPackages = [
        pkgs.ipset
        pkgs.coreutils
        pkgs.gawk
      ];
      extraCommands = lib.mkBefore ''
        # Set the default policies
        iptables -w -P INPUT DROP
        iptables -w -P FORWARD DROP
        iptables -w -P OUTPUT ACCEPT

        # delete ctstate RELATED,ESTABLISHED and lo rules 
        iptables -w -D nixos-fw -i lo -j nixos-fw-accept
        iptables -w -D nixos-fw -m conntrack --ctstate ESTABLISHED,RELATED -j nixos-fw-accept

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
        iptables -w  -t mangle -N ghaf-fw-pre-mangle 2> /dev/null || true
        iptables -w -t mangle -I PREROUTING -j ghaf-fw-pre-mangle 2> /dev/null || true
        iptables -w -t nat -N ghaf-fw-pre-nat 2> /dev/null || true
        iptables  -w -t nat -I PREROUTING -j ghaf-fw-pre-nat 2> /dev/null || true

        #Create custom chain for INPUT
        iptables -w  -t filter -N ghaf-fw-in-filter  2> /dev/null || true
        iptables -w -t filter -I INPUT -j ghaf-fw-in-filter  2> /dev/null || true

        # Create custom chain for FORWARD
        iptables -w  -N ghaf-fw-fwd-filter 2> /dev/null || true
        iptables -w  -I FORWARD -j ghaf-fw-fwd-filter 2> /dev/null || true


        # Create custom chain for OUTPUT
        iptables -w -t filter -N ghaf-fw-out-filter 2> /dev/null || true
        iptables -w -t filter -I OUTPUT -j ghaf-fw-out-filter 2> /dev/null || true

        # Create custom chain for POSTROUTING
        iptables -w -t nat -N ghaf-fw-post-nat 2> /dev/null || true
        iptables -w -t nat -I POSTROUTING -j ghaf-fw-post-nat 2> /dev/null || true

        # Create custom chain to add debug features for mangle tables
        iptables -w -t mangle -N ghaf-fw-mangle-drop 2> /dev/null || true
        iptables -w -t mangle -A ghaf-fw-mangle-drop -j DROP

        # Create custom chain to add debug features for filter tables
        iptables -w -t filter -N ghaf-fw-filter-drop 2> /dev/null || true
        iptables -w -t filter -A ghaf-fw-filter-drop -j DROP

        ### PREROUTING rules ###

        # Drop invalid packets
        iptables -w -t mangle -A ghaf-fw-pre-mangle -m conntrack --ctstate INVALID -j ghaf-fw-mangle-drop
        # Block packets with bogus TCP flags  
        iptables -w -t mangle -A ghaf-fw-pre-mangle -p tcp --tcp-flags FIN,SYN,RST,PSH,ACK,URG NONE -j ghaf-fw-mangle-drop
        iptables -w -t mangle -A ghaf-fw-pre-mangle -p tcp --tcp-flags FIN,SYN FIN,SYN -j ghaf-fw-mangle-drop
        iptables -w -t mangle -A ghaf-fw-pre-mangle -p tcp --tcp-flags SYN,RST SYN,RST -j ghaf-fw-mangle-drop
        iptables -w -t mangle -A ghaf-fw-pre-mangle -p tcp --tcp-flags FIN,RST FIN,RST -j ghaf-fw-mangle-drop
        iptables -w -t mangle -A ghaf-fw-pre-mangle -p tcp --tcp-flags FIN,ACK FIN -j ghaf-fw-mangle-drop
        iptables -w -t mangle -A ghaf-fw-pre-mangle -p tcp --tcp-flags ACK,URG URG -j ghaf-fw-mangle-drop
        iptables -w -t mangle -A ghaf-fw-pre-mangle -p tcp --tcp-flags ACK,FIN FIN -j ghaf-fw-mangle-drop
        iptables -w -t mangle -A ghaf-fw-pre-mangle -p tcp --tcp-flags ACK,PSH PSH -j ghaf-fw-mangle-drop
        iptables -w -t mangle -A ghaf-fw-pre-mangle -p tcp --tcp-flags ALL ALL -j ghaf-fw-mangle-drop
        iptables -w -t mangle -A ghaf-fw-pre-mangle -p tcp --tcp-flags ALL NONE -j ghaf-fw-mangle-drop
        iptables -w -t mangle -A ghaf-fw-pre-mangle -p tcp --tcp-flags ALL FIN,PSH,URG -j ghaf-fw-mangle-drop
        iptables -w -t mangle -A ghaf-fw-pre-mangle -p tcp --tcp-flags ALL SYN,FIN,PSH,URG -j ghaf-fw-mangle-drop
        iptables -w -t mangle -A ghaf-fw-pre-mangle -p tcp --tcp-flags ALL SYN,RST,ACK,FIN,URG -j ghaf-fw-mangle-drop

        ### INPUT rules ###
        iptables -w -A ghaf-fw-in-filter -i lo -j ACCEPT
        iptables -w -A ghaf-fw-in-filter -p icmp --icmp-type echo-request -m limit --limit 1/minute --limit-burst 5 -j ACCEPT
        iptables -w -A ghaf-fw-in-filter -p icmp --icmp-type echo-request -j ghaf-fw-filter-drop
        iptables -w -A ghaf-fw-in-filter -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT

        # nixos-fw-accept should be flushed to inject our rules
        iptables -w -F nixos-fw-accept 2> /dev/null || true
        iptables -w -A nixos-fw-accept -p tcp --syn -m conntrack --ctstate NEW -j ACCEPT
        iptables -w -A nixos-fw-accept -p udp -m conntrack --ctstate NEW  -j ACCEPT
        iptables -w -A nixos-fw-accept -j nixos-fw-log-refuse

        ### OUTPUT rules ###
        iptables -w -I OUTPUT -o lo -j ACCEPT  

        ### POSTROUTING rules ###

        ### Inject the other rules ### 
        ${lib.optionalString (cfg.extra.prerouting.mangle != [ ]) (
          addIptablesRules "mangle" "ghaf-fw-pre-mangle" cfg.extra.prerouting.mangle
        )}
        ${lib.optionalString (cfg.extra.prerouting.nat != [ ]) (
          addIptablesRules "nat" "ghaf-fw-pre-nat" cfg.extra.prerouting.nat
        )}
        ${lib.optionalString (cfg.extra.input.filter != [ ]) (
          addIptablesRules "filter" "ghaf-fw-in-filter" cfg.extra.input.filter
        )}
        ${lib.optionalString (cfg.extra.forward.filter != [ ]) (
          addIptablesRules "filter" "ghaf-fw-fwd-filter" cfg.extra.forward.filter
        )}
        ${lib.optionalString (cfg.extra.output.filter != [ ]) (
          addIptablesRules "filter" "ghaf-fw-out-filter" cfg.extra.output.filter
        )}
        ${lib.optionalString (cfg.extra.postrouting.nat != [ ]) (
          addIptablesRules "nat" "ghaf-fw-post-nat" cfg.extra.postrouting.nat
        )}

      '';
    }
    // cfg.extraOptions;

  };
}
