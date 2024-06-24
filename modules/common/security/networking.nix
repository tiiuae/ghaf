# Copyright 2024-2025 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  config,
  lib,
  ...
}: let
  cfg = config.ghaf.security.network;
in {
  ## Option to enable IP security
  options.ghaf.security.network.ipsecurity.enable = lib.mkOption {
    description = ''
      Enable Internet Protocol security.
    '';
    type = lib.types.bool;
    default = true;
  };

  options.ghaf.security.network.bpf-access-level = lib.mkOption {
    description = ''
      Aceess level for bpf:
        0: disable bpf JIT
        1: priviledged access only
        no restriction for any other value
    '';
    type = lib.types.int;
    default = 0;
  };

  config.boot.kernel.sysctl = lib.mkMerge [
    (lib.mkIf cfg.ipsecurity.enable {
      # Disable IPv6
      "net.ipv6.conf.all.disable_ipv6" = lib.mkForce 1;
      "net.ipv6.conf.default.disable_ipv6" = lib.mkForce 1;
      "net.ipv6.conf.lo.disable_ipv6" = lib.mkForce 1;

      # Prevent SYN flooding
      "net.ipv4.tcp_syncookies" = lib.mkForce 1;
      "net.ipv4.tcp_syn_retries" = lib.mkForce 2;
      "net.ipv4.tcp_synack_retries" = lib.mkForce 2;
      "net.ipv4.tcp_max_syn_backlog" = lib.mkForce 4096;

      # Drop RST packets for sockets in the time-wait state
      "net.ipv4.tcp_rfc1337" = lib.mkForce 1;

      # Enable RP Filter
      "net.ipv4.conf.all.rp_filter" = lib.mkForce 1;
      "net.ipv4.conf.default.rp_filter" = lib.mkForce 1;

      # Disable redirect acceptance
      "net.ipv4.conf.all.accept_redirects" = lib.mkForce 0;
      "net.ipv4.conf.default.accept_redirects" = lib.mkForce 0;
      "net.ipv4.conf.all.secure_redirects" = lib.mkForce 0;
      "net.ipv4.conf.default.secure_redirects" = lib.mkForce 0;
      "net.ipv4.conf.all.send_redirects" = lib.mkForce 0;
      "net.ipv4.conf.default.send_redirects" = lib.mkForce 0;

      # Ignore source-routed IP packets
      "net.ipv4.conf.all.accept_source_route" = lib.mkForce 0;
      "net.ipv4.conf.default.accept_source_route" = lib.mkForce 0;

      # Ignore ICMP echo requests
      "net.ipv4.icmp_echo_ignore_all" = lib.mkForce 1;

      # Log Martian packets
      "net.ipv4.conf.all.log_martians" = lib.mkDefault 0;
      "net.ipv4.conf.default.log_martians" = lib.mkDefault 0;

      # Ignore bogus ICMP error responses
      "net.ipv4.icmp_ignore_bogus_error_responses" = lib.mkForce 1;
    })

    (lib.mkIf (cfg.bpf-access-level == 0) {
      # Disable BPF JIT compiler (to eliminate spray attacks)
      "net.core.bpf_jit_enable" = lib.mkDefault false;
    })

    (lib.mkIf (cfg.bpf-access-level == 1) {
      # Provide BPF access to privileged users
      # TODO: test if it works with Tetragon/Suricata
      "kernel.unprivileged_bpf_disabled" = lib.mkOverride 500 1;
      "net.core.bpf_jit_harden" = lib.mkForce 2;
    })
  ];
}
