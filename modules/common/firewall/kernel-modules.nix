# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# Module which adds option ghaf.firewall.kernel-modules.enable.
#
# Adds bunch of modules to the kernel, so firewall can start, as our custom
# kernels don't seem to always have all necessary modules enabled.
#
{ config, lib, ... }:
let
  cfg = config.ghaf.firewall.kernel-modules;
in
{
  _file = ./kernel-modules.nix;

  options.ghaf.firewall.kernel-modules = {
    enable = lib.mkEnableOption "kernel modules required for firewall";
  };

  config = lib.mkIf cfg.enable {

    boot.kernelPatches = [
      {
        name = "firewall-modules-enable";
        patch = null;
        structuredExtraConfig = with lib.kernel; {
          NETFILTER_NETLINK_LOG = module;

          NETFILTER_XTABLES = yes;
          NETFILTER_XT_MATCH_CONNTRACK = module;
          NETFILTER_XT_MATCH_PKTTYPE = module;
          NETFILTER_XT_TARGET_CHECKSUM = module;
          NETFILTER_XT_TARGET_CLASSIFY = module;
          NETFILTER_XT_TARGET_CONNMARK = module;
          NETFILTER_XT_TARGET_IDLETIMER = module;
          NETFILTER_XT_TARGET_LOG = module;
          NETFILTER_XT_TARGET_MARK = module;
          NETFILTER_XT_TARGET_MASQUERADE = module;
          NETFILTER_XT_TARGET_NETMAP = module;
          NETFILTER_XT_TARGET_NFLOG = module;
          NETFILTER_XT_TARGET_REDIRECT = module;
          NETFILTER_XT_TARGET_TCPMSS = module;
          NETFILTER_XT_TARGET_TEE = module;
          NETFILTER_XT_TARGET_TPROXY = module;
          NETFILTER_XT_MATCH_LIMIT = module;
          NETFILTER_XT_MATCH_HASHLIMIT = module;
          NETFILTER_XT_MATCH_MULTIPORT = module;
          NETFILTER_XT_MATCH_COMMENT = module;
          NETFILTER_XT_SET = module;
          NETFILTER_XT_MATCH_SOCKET = module;
          NETFILTER_XT_MATCH_MARK = module;
          NETFILTER_XT_MATCH_STATE = module;
          NETFILTER_XT_MATCH_CONNMARK = module;

          IP_SET = module;
          IP_SET_HASH_IP = module;
          IP_SET_HASH_IPMARK = module;

          NF_CONNTRACK = module;
          NF_CONNTRACK_AMANDA = module;
          NF_CONNTRACK_BROADCAST = module;
          NF_CONNTRACK_EVENTS = yes;
          NF_CONNTRACK_FTP = module;
          NF_CONNTRACK_H323 = module;
          NF_CONNTRACK_IRC = module;
          NF_CONNTRACK_MARK = yes;
          NF_CONNTRACK_NETBIOS_NS = module;
          NF_CONNTRACK_PPTP = module;
          NF_CONNTRACK_PROCFS = yes;
          NF_CONNTRACK_SANE = module;
          NF_CONNTRACK_SIP = module;
          NF_CONNTRACK_TFTP = module;
          NF_CONNTRACK_TIMEOUT = yes;
          NF_CONNTRACK_TIMESTAMP = yes;
          NF_CONNTRACK_ZONES = yes;
          NF_CT_NETLINK = module;
          NF_CT_PROTO_GRE = yes;
          NF_CT_PROTO_SCTP = yes;
          NF_CT_PROTO_UDPLITE = yes;
          NF_DEFRAG_IPV4 = module;
          NF_DEFRAG_IPV6 = module;
          NF_DUP_IPV4 = module;
          NF_DUP_IPV6 = module;
          NF_LOG_ARP = module;
          NF_LOG_IPV4 = module;
          NF_LOG_IPV6 = module;
          NF_NAT = module;
          NF_NAT_AMANDA = module;
          NF_NAT_FTP = module;
          NF_NAT_H323 = module;
          NF_NAT_IRC = module;
          NF_NAT_MASQUERADE = yes;
          NF_NAT_PPTP = module;
          NF_NAT_REDIRECT = yes;
          NF_NAT_SIP = module;
          NF_NAT_TFTP = module;
          NF_REJECT_IPV4 = module;
          NF_REJECT_IPV6 = module;
          NF_SOCKET_IPV4 = module;
          NF_SOCKET_IPV6 = module;
          NF_TABLES = module;
          NF_TABLES_ARP = yes;
          NF_TABLES_BRIDGE = module;
          NF_TABLES_INET = yes;
          NF_TABLES_IPV4 = yes;
          NF_TABLES_IPV6 = yes;
          NF_TABLES_NETDEV = yes;
          NF_TPROXY_IPV4 = module;
          NF_TPROXY_IPV6 = module;

          NFT_REDIR = module;
          NFT_CT = module;
          NFT_LIMIT = module;
          NFT_CONNLIMIT = module;
          NFT_COMPAT = module;
          NFT_LOG = module;
          NFT_MASQ = module;
          NFT_NAT = module;
          NFT_REJECT = module;
        };
      }
    ];
  };
}
