// SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
// SPDX-License-Identifier: Apache-2.0

#include <linux/bpf.h>
#include <linux/if_ether.h>
#include <linux/in.h>
#include <linux/ip.h>

#define SEC(name) __attribute__((section(name), used))

// cls_bpf without direct-action: -1 runs the filter's actions (mirred), 0 skips them.
#define MIRROR -1
#define SKIP 0

#define IP_OFFSET 0x1fff
#define LIBBPF_PIN_BY_NAME 1

#if __BYTE_ORDER__ == __ORDER_LITTLE_ENDIAN__
#define bpf_htons(x) __builtin_bswap16(x)
#else
#define bpf_htons(x) (x)
#endif

#ifdef HOOK_INGRESS
#define DIR 1
#else
#define DIR 0
#endif

static void *(*bpf_map_lookup_elem)(void *map, const void *key) = (void *)BPF_FUNC_map_lookup_elem;
static long (*bpf_map_update_elem)(void *map, const void *key, const void *value,
                                   __u64 flags) = (void *)BPF_FUNC_map_update_elem;
static long (*bpf_skb_load_bytes_relative)(const void *skb, __u32 offset, void *to, __u32 len,
                                           __u32 start_header) =
    (void *)BPF_FUNC_skb_load_bytes_relative;

// libbpf's BTF map definition macros (bpf_helpers.h); libbpf 1.0 dropped the legacy `maps` section.
#define __uint(name, val) int(*name)[val]
#define __type(name, val) typeof(val) *name

// Always the outgoing direction's tuple, so both hooks find the same entry.
struct flow {
  __u32 saddr;
  __u32 daddr;
  __u16 sport;
  __u16 dport;
  __u8 proto;
  __u8 pad[3];
};

// Index 0 counts egress, 1 ingress; each direction gets its own budget.
struct counters {
  __u64 bytes[2];
  __u64 pkts[2];
  __u64 max_bytes;
  __u64 max_pkts;
};

#include "flow-limits.h"

struct {
  __uint(type, BPF_MAP_TYPE_LRU_HASH);
  __uint(max_entries, 16384);
  __type(key, struct flow);
  __type(value, struct counters);
  __uint(pinning, LIBBPF_PIN_BY_NAME);
} mirror_flows SEC(".maps");

SEC("classifier")
int flow_head(struct __sk_buff *skb)
{
  struct iphdr ip;
  struct flow key = {};
  struct counters *c;
  __u16 ports[2] = {};
  // A GRO/GSO skb carries several wire packets.
  __u64 segs = skb->gso_segs ? skb->gso_segs : 1;

  // Anything this cannot key is mirrored rather than missed.
  if (skb->protocol != bpf_htons(ETH_P_IP))
    return MIRROR;
  // Reads the linear area only, and never makes the cloned skb writable.
  if (bpf_skb_load_bytes_relative(skb, 0, &ip, sizeof(ip), BPF_HDR_START_NET))
    return MIRROR;
  if (ip.frag_off & bpf_htons(IP_OFFSET))
    return MIRROR;
  if (ip.protocol == IPPROTO_TCP || ip.protocol == IPPROTO_UDP) {
    if (bpf_skb_load_bytes_relative(skb, ip.ihl * 4, ports, sizeof(ports), BPF_HDR_START_NET))
      return MIRROR;
  }

  key.proto = ip.protocol;
#ifdef HOOK_INGRESS
  key.saddr = ip.daddr;
  key.daddr = ip.saddr;
  key.sport = ports[1];
  key.dport = ports[0];
#else
  key.saddr = ip.saddr;
  key.daddr = ip.daddr;
  key.sport = ports[0];
  key.dport = ports[1];
#endif

  c = bpf_map_lookup_elem(&mirror_flows, &key);
  if (!c) {
#ifdef HOOK_INGRESS
    // Nothing of this flow has left yet: unsolicited, and the firewall drops it.
    return SKIP;
#else
    struct counters init = {};
    set_limits(&init, key.proto, bpf_htons(key.dport));
    init.bytes[DIR] = skb->len;
    init.pkts[DIR] = segs;
    bpf_map_update_elem(&mirror_flows, &key, &init, BPF_NOEXIST);
    return MIRROR;
#endif
  }
  if (c->bytes[DIR] >= c->max_bytes || c->pkts[DIR] >= c->max_pkts)
    return SKIP;
  __sync_fetch_and_add(&c->bytes[DIR], skb->len);
  __sync_fetch_and_add(&c->pkts[DIR], segs);
  return MIRROR;
}

char _license[] SEC("license") = "GPL";
