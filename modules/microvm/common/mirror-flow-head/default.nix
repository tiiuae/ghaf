# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# tc classifiers that match only the head of each flow the host opened, so the
# mirred action behind them clones just that. Builds ingress.o and egress.o,
# which share one pinned map.
{
  lib,
  runCommand,
  writeText,
  clang,
  linuxHeaders,
  flowBytes,
  flowLimits ? import ./limits.nix,
}:
let
  protoNumber = {
    tcp = 6;
    udp = 17;
  };
  limit = value: if value == null then "~0ULL" else "${toString value}ULL";
  limitsHeader = writeText "flow-limits.h" ''
    static __attribute__((always_inline)) void set_limits(struct counters *c, __u8 proto, __u16 port)
    {
    ${lib.concatMapStrings (entry: ''
      if (proto == ${toString protoNumber.${entry.proto}} && port == ${toString entry.port}) {
        c->max_bytes = ${limit (entry.bytes or null)};
        c->max_pkts = ${limit (entry.packets or null)};
        return;
      }
    '') flowLimits}
      c->max_bytes = ${toString flowBytes}ULL;
      c->max_pkts = ~0ULL;
    }
  '';
in
runCommand "mirror-flow-head"
  {
    nativeBuildInputs = [
      clang
      linuxHeaders
    ];
    # cc-wrapper's hardening flags are rejected by clang for -target bpf;
    # the BPF verifier is the real safety net.
    hardeningDisable = [ "all" ];
  }
  ''
    mkdir $out
    cp ${limitsHeader} flow-limits.h
    for hook in ingress egress; do
      clang -O2 -g -target bpf -I. -DHOOK_''${hook^^} \
        -idirafter ${linuxHeaders}/include -c ${./flow-head.bpf.c} -o $out/$hook.o
    done
  ''
