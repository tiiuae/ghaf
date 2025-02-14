# Copyright 2024-2025 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  config,
  lib,
  ...
}:
let
  cfg = config.ghaf.security.sysctl.network;
  inherit (lib)
    mkOption
    mkForce
    mkDefault
    mkIf
    mkMerge
    mkOverride
    types
    ;
in
{
  ## Options to enable IP security
  options.ghaf.security.sysctl.network = {
    enable = mkOption {
      description = ''
        Enables sysctl network security configuration.
      '';
      type = types.bool;
      default = true;
    };

    prevent-syn-flooding = mkOption {
      description = ''
        Prevent SYN packet flooding.
        It is recommended to reduce attack surface by disabling IPv6 if it is not being used.
        References:
        https://www.tenable.com/audits/items/CIS_AlmaLinux_OS_8_Server_v1.0.0_L2.audit:a532993e3ac29c19c0d491463a881303
        https://linux-audit.com/linux-security-guide-for-hardening-ipv6/
      '';
      type = types.bool;
      default = true;
    };

    enable-RFC_1337-protection = mkOption {
      description = ''
        Enable RFC 1337 fix to protect against TIME-WAIT assassination attacks or unintended connection resets.
        References:
        https://wiki.archlinux.org/title/Talk:Sysctl
        https://datatracker.ietf.org/doc/html/rfc1337
      '';
      type = types.bool;
      default = true;
    };

    enable-rp-filter = mkOption {
      description = ''
        Enable reverse path filtering to protect against IP address spoofing.
        References:
        https://www.tenable.com/audits/items/CIS_Amazon_Linux_2_STIG_v1.0.0_L1.audit:8a082faa85bd75cf16b791cada7d6caf
        https://docs.vmware.com/en/vRealize-Operations/8.10/com.vmware.vcom.core.doc/GUID-0AAA4D96-5FDE-49A7-8BB3-D7F56C89137C.html
      '';
      type = types.bool;
      default = false;
    };

    disable-icmp-redirect-acceptance = mkOption {
      description = ''
        Disable ICMP redirect acceptance to protect against routing-based exploits.
        Reference:
        https://www.tenable.com/audits/items/CIS_Debian_Linux_7_v1.0.0_L1.audit:afddab3eeba4b46856ca171913034f63
      '';
      type = types.bool;
      default = true;
    };

    ignore-source-routed-ippackets = mkOption {
      description = ''
        Don't accept source routed IP packets to protect internal addressed from outside world.
        Reference:
        https://www.tenable.com/audits/items/CIS_Red_Hat_EL5_v2.2.1_L1.audit:0df0d28b8145e0c83c9a9e11c185644a
      '';
      type = types.bool;
      default = true;
    };

    disable-ping-request = mkOption {
      description = ''
        Disable all ping requests.
        Reference:
        https://www.tenable.com/audits/items/CIS_Rocky_Linux_8_v1.0.0_L1_Server.audit:a82dbeb614529af0ccae791e4e56cf89
      '';
      type = types.bool;
      default = false;
    };

    log-martian-packets = mkOption {
      description = ''
        Log packets with invalid source address. These packets may indicate attacks in progress.
        Reference:
        https://www.tenable.com/audits/items/DISA_STIG_RHEL_5_v1r17.audit:a81d94e68acab6935d781540fe440116
      '';
      type = types.bool;
      default = true;
    };

    ignore-bogus-icmp-response = mkOption {
      description = ''
        Avoid useless logging by ignoring bogus ICMP responses (RFC 1122).
        Reference:
        https://www.tenable.com/audits/items/Tenable_Best_Practices_Cisco_Firepower_Management_Center_OS.audit:d942e12989d33d8098dae6bec57e0ce3
      '';
      type = types.bool;
      default = true;
    };

    bpf-access-level = mkOption {
      description = ''
        Access level for bpf:
          0: disable bpf JIT
          1: priviledged access only
          no restriction for any other value
        Reference:
        https://www.tenable.com/audits/items/DISA_STIG_Oracle_Linux_8_v1r8.audit:fdbbd872a011596fbd5cba5103f3e4ef
      '';
      type = types.int;
      default = 1;
    };
  };

  config.boot.kernel.sysctl = mkMerge [
    # Prevent SYN flooding
    (mkIf (cfg.prevent-syn-flooding && cfg.enable) {
      "net.ipv4.tcp_syncookies" = mkForce 1;
      "net.ipv4.tcp_syn_retries" = mkForce 2;
      "net.ipv4.tcp_synack_retries" = mkForce 2;
      "net.ipv4.tcp_max_syn_backlog" = mkForce 1280;
    })

    # Drop RST packets for sockets in the time-wait state
    (mkIf (cfg.enable-RFC_1337-protection && cfg.enable) {
      "net.ipv4.tcp_rfc1337" = mkForce 1;
    })

    # Enable RP Filter
    (mkIf (cfg.enable-rp-filter && cfg.enable) {
      "net.ipv4.conf.all.rp_filter" = mkForce 1;
      "net.ipv4.conf.default.rp_filter" = mkForce 1;
    })

    # Disable redirect acceptance
    (mkIf (cfg.disable-icmp-redirect-acceptance && cfg.enable) {
      "net.ipv6.conf.all.accept_redirects" = mkForce 0;
      "net.ipv6.conf.default.accept_redirects" = mkForce 0;
      "net.ipv4.conf.all.accept_redirects" = mkForce 0;
      "net.ipv4.conf.default.accept_redirects" = mkForce 0;
      "net.ipv4.conf.all.secure_redirects" = mkForce 0;
      "net.ipv4.conf.default.secure_redirects" = mkForce 0;
      "net.ipv4.conf.all.send_redirects" = mkForce 0;
      "net.ipv4.conf.default.send_redirects" = mkForce 0;
    })

    # Ignore source routed IP packets
    (mkIf (cfg.ignore-source-routed-ippackets && cfg.enable) {
      "net.ipv4.conf.all.accept_source_route" = mkForce 0;
      "net.ipv4.conf.default.accept_source_route" = mkForce 0;
      "net.ipv6.conf.all.accept_source_route" = mkForce 0;
      "net.ipv6.conf.default.accept_source_route" = mkForce 0;
    })

    # Disable ping
    (mkIf (cfg.disable-ping-request && cfg.enable) {
      "net.ipv4.icmp_echo_ignore_all" = mkForce 1;
      # "net.ipv4.icmp_echo_ignore_broadcasts" = mkForce 1;
    })

    # Log Martian packets
    (mkIf (cfg.log-martian-packets && cfg.enable) {
      "net.ipv4.conf.all.log_martians" = mkDefault 1;
      "net.ipv4.conf.default.log_martians" = mkDefault 1;
    })

    # Ignore bogus ICMP error responses
    (mkIf (cfg.ignore-bogus-icmp-response && cfg.enable) {
      "net.ipv4.icmp_ignore_bogus_error_responses" = mkForce 1;
    })

    (mkIf (cfg.bpf-access-level == 0) {
      # Disable BPF JIT compiler (to eliminate spray attacks)
      "net.core.bpf_jit_enable" = mkDefault false;
    })
    (mkIf (cfg.bpf-access-level == 1) {
      # Provide BPF access to privileged users
      # TODO: test if it works with Tetragon/Suricata
      "kernel.unprivileged_bpf_disabled" = mkOverride 500 1;
      "net.core.bpf_jit_harden" = mkForce 2;
    })
  ];
}
