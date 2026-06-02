# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# L2 Traffic Mirror Module for IDS-VM
#
# Provides two roles:
#   sender   — mirrors physical NIC traffic to a tap (tap-mirror-<hostname>)
#   receiver — IDS-VM side: receives mirrored frames on the mirror interface
#
# The host relays frames between sender and receiver taps via TC redirect
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.ghaf.virtualization.microvm.trafficMirror;

  mirrorSenderMac = "02:AD:00:00:FF:01";
  mirrorReceiverMac = "02:AD:00:00:FF:02";

  hostTapId = "mir-${config.networking.hostName}";

  idsMirrorBench = pkgs.writeShellScriptBin "ids-mirror-bench" ''
    exec ${lib.getExe pkgs.ids-mirror-bench} "$@"
  '';

  # eBPF classifier that truncates mirrored frames to cfg.sender.snaplen bytes.
  # Attached on the `mirror` tap's own egress, downstream of the mirred clone
  # (see mirrorStartScript) - by that point the frame is already an
  # independent copy, so shrinking it here never touches live traffic.
  mirrorTruncSrc = pkgs.writeText "mirror-trunc.bpf.c" ''
    #include <linux/bpf.h>

    #define SEC(name) __attribute__((section(name), used))
    #define TC_ACT_OK 0

    static long (*bpf_skb_change_tail)(struct __sk_buff *skb, __u32 len, __u64 flags) = (void *) 38;

    SEC("classifier")
    int mirror_truncate(struct __sk_buff *skb)
    {
        if (skb->len > ${toString cfg.sender.snaplen})
            bpf_skb_change_tail(skb, ${toString cfg.sender.snaplen}, 0);
        return TC_ACT_OK;
    }

    char _license[] SEC("license") = "GPL";
  '';

  mirrorTruncObj =
    pkgs.runCommand "mirror-trunc.o"
      {
        nativeBuildInputs = [
          pkgs.clang
          pkgs.linuxHeaders
        ];
        # nixpkgs' cc-wrapper injects hardening flags (e.g.
        # -fzero-call-used-regs, -fstack-protector-strong) that clang
        # rejects for -target bpf; the BPF verifier is the real safety net
        # here anyway.
        hardeningDisable = [ "all" ];
      }
      ''
        clang -O2 -target bpf -idirafter ${pkgs.linuxHeaders}/include \
          -c ${mirrorTruncSrc} -o $out
      '';

  mirrorStartScript = pkgs.writeShellApplication {
    name = "ids-mirror-start";
    runtimeInputs = [
      pkgs.iproute2
    ];
    text = ''
      # Run tc cleanup; log output but never abort on failure (qdisc may not exist yet).
      tc_try() { "$@" 2>&1 || true; }

      # Accumulate mirrored packets in slots before sending to ids-vm.
      # virtio's xmit_more defers the doorbell write until the last packet in a burst.
      # This helps reduce CPU usage when mirroring high packet rates.
      tc_try tc qdisc del dev mirror root
      tc qdisc add dev mirror root netem ${cfg.sender.netem} \
        || { echo "ids-mirror: ERROR: failed to add netem qdisc on mirror" >&2; exit 1; }

      ${lib.optionalString (cfg.sender.snaplen != null) ''
        # Truncate mirrored frames to ${toString cfg.sender.snaplen} bytes on
        # the mirror tap's own egress, before they hit the netem queue above -
        # this shrinks everything downstream (queueing, virtio, host relay,
        # ids-vm receive) to header-only size.
        tc_try tc filter del dev mirror egress
        tc_try tc qdisc del dev mirror clsact
        tc qdisc add dev mirror clsact \
          || { echo "ids-mirror: ERROR: failed to add clsact qdisc on mirror" >&2; exit 1; }
        tc filter add dev mirror egress bpf da obj ${mirrorTruncObj} sec classifier \
          || { echo "ids-mirror: ERROR: failed to add truncate filter on mirror" >&2; exit 1; }
      ''}

      mirrored=0

      ${lib.optionalString cfg.sender.mirrorExternalInterfaces ''
        ${lib.optionalString cfg.sender.rps.enable ''
          sysctl -w net.core.rps_sock_flow_entries=32768 >/dev/null 2>&1 || true
        ''}
        for sysfs in /sys/class/net/*; do
          name=$(basename "$sysfs")
          [ -e "$sysfs/device" ] || continue
          [[ "$name" == "mirror" ]] && continue
          driver=$(basename "$(readlink "$sysfs/device/driver")" 2>/dev/null) || true
          [ "$driver" = "virtio_net" ] && continue

          echo "ids-mirror: mirroring external $name -> mirror"

          tc_try tc filter del dev "$name" ingress
          tc_try tc filter del dev "$name" egress
          tc_try tc qdisc  del dev "$name" clsact
          tc qdisc  add dev "$name" clsact \
            || { echo "ids-mirror: ERROR: failed to add clsact qdisc on $name" >&2; exit 1; }
          # Low-value/high-volume traffic excluded from the mirror, evaluated
          # (in pref order) before the catch-all at pref 10 so matching
          # frames terminate (pass) before mirred ever sees them. DNS is
          # deliberately NOT excluded here.
          #
          # Multicast/broadcast (dst MAC I/G bit set): mDNS/SSDP/IGMP chatter,
          # and also covers LLDP/CDP/STP since their standard destination
          # MACs are multicast-addressed - no separate rule needed for those.
          #
          # Uses flower's dst_mac match (dissected field), NOT a raw u32 byte
          # offset at 0. On egress, u32's "at 0" isn't reliably anchored to
          # the L2 header for locally-originated traffic - it can land on the
          # IP header instead, and an ordinary IPv4 packet's first byte
          # (0x45, version+IHL) has its LSB set, misclassifying it as
          # multicast. flower reads the real dissected MAC field regardless
          # of direction.
          tc filter add dev "$name" ingress protocol all pref 1 \
            flower dst_mac 01:00:00:00:00:00/01:00:00:00:00:00 action pass \
            || { echo "ids-mirror: ERROR: failed to add multicast-exclude filter on $name ingress" >&2; exit 1; }
          tc filter add dev "$name" egress protocol all pref 1 \
            flower dst_mac 01:00:00:00:00:00/01:00:00:00:00:00 action pass \
            || { echo "ids-mirror: ERROR: failed to add multicast-exclude filter on $name egress" >&2; exit 1; }
          # ARP
          tc filter add dev "$name" ingress protocol arp pref 2 flower action pass \
            || { echo "ids-mirror: ERROR: failed to add ARP-exclude filter on $name ingress" >&2; exit 1; }
          tc filter add dev "$name" egress protocol arp pref 2 flower action pass \
            || { echo "ids-mirror: ERROR: failed to add ARP-exclude filter on $name egress" >&2; exit 1; }
          # ICMP + NTP (UDP/123, both port directions) - one shared pref/protocol
          # band per direction: flower keeps all rules added at the same pref
          # in a single hash table with one key-extraction pass, instead of
          # each rule paying its own separate classifier traversal.
          tc filter add dev "$name" ingress protocol ip pref 3 flower ip_proto icmp action pass \
            || { echo "ids-mirror: ERROR: failed to add ICMP-exclude filter on $name ingress" >&2; exit 1; }
          tc filter add dev "$name" egress protocol ip pref 3 flower ip_proto icmp action pass \
            || { echo "ids-mirror: ERROR: failed to add ICMP-exclude filter on $name egress" >&2; exit 1; }
          tc filter add dev "$name" ingress protocol ip pref 3 flower ip_proto udp dst_port 123 action pass \
            || { echo "ids-mirror: ERROR: failed to add NTP-exclude filter on $name ingress" >&2; exit 1; }
          tc filter add dev "$name" egress protocol ip pref 3 flower ip_proto udp dst_port 123 action pass \
            || { echo "ids-mirror: ERROR: failed to add NTP-exclude filter on $name egress" >&2; exit 1; }
          tc filter add dev "$name" ingress protocol ip pref 3 flower ip_proto udp src_port 123 action pass \
            || { echo "ids-mirror: ERROR: failed to add NTP-exclude filter (src) on $name ingress" >&2; exit 1; }
          tc filter add dev "$name" egress protocol ip pref 3 flower ip_proto udp src_port 123 action pass \
            || { echo "ids-mirror: ERROR: failed to add NTP-exclude filter (src) on $name egress" >&2; exit 1; }
          # IPv6, excluded entirely (DNS over IPv4 is unaffected)
          tc filter add dev "$name" ingress protocol ipv6 pref 4 flower action pass \
            || { echo "ids-mirror: ERROR: failed to add IPv6-exclude filter on $name ingress" >&2; exit 1; }
          tc filter add dev "$name" egress protocol ipv6 pref 4 flower action pass \
            || { echo "ids-mirror: ERROR: failed to add IPv6-exclude filter on $name egress" >&2; exit 1; }
          # matchall instead of u32 match-all: skips u32's hash-dispatch setup
          # for a rule that unconditionally matches every remaining packet.
          tc filter add dev "$name" ingress protocol all pref 10 \
            matchall action mirred egress mirror dev mirror \
            || { echo "ids-mirror: ERROR: failed to add ingress filter on $name" >&2; exit 1; }
          tc filter add dev "$name" egress protocol all pref 10 \
            matchall action mirred egress mirror dev mirror \
            || { echo "ids-mirror: ERROR: failed to add egress filter on $name" >&2; exit 1; }

          ${lib.optionalString cfg.sender.rps.enable ''
            # RPS: each interface gets its own distinct CPU (round-robin over
            # however many net-vm actually has, via nproc - not hardcoded),
            # instead of every interface sharing the same mask and contending
            # for the same cores.
            rps_cpu=$((mirrored % $(nproc)))
            rps_mask=$(printf '%x' $((1 << rps_cpu)))
            rps_f="$sysfs/queues/rx-0/rps_cpus"
            rps_fc="$sysfs/queues/rx-0/rps_flow_cnt"
            if [ -e "$rps_f" ]; then
              echo "$rps_mask" > "$rps_f" 2>/dev/null || true
              [ -e "$rps_fc" ] && { echo 32768 > "$rps_fc" 2>/dev/null || true; }
              echo "ids-mirror: rps on $name -> cpu$rps_cpu (mask=$rps_mask)"
            fi
          ''}

          mirrored=$((mirrored + 1))
        done
      ''}

      [ "$mirrored" -gt 0 ] || { echo "ids-mirror: no interfaces configured for mirroring" >&2; exit 1; }
      echo "ids-mirror: mirroring $mirrored interface(s) to mirror"
    '';
  };

  mirrorHotplugScript = pkgs.writeShellApplication {
    name = "ids-mirror-usb-hotplug";
    runtimeInputs = [ pkgs.iproute2 ];
    text = ''
      tc_try() { "$@" 2>&1 || true; }

      name="$1"
      [ -e "/sys/class/net/mirror" ] || { echo "ids-mirror: mirror tap not ready, skipping $name" >&2; exit 0; }
      echo "ids-mirror: hotplug $name -> mirror"
      tc_try tc filter del dev "$name" ingress
      tc_try tc filter del dev "$name" egress
      tc_try tc qdisc  del dev "$name" clsact
      tc qdisc  add dev "$name" clsact \
        || { echo "ids-mirror: ERROR: failed to add clsact qdisc on $name" >&2; exit 1; }
      tc filter add dev "$name" ingress protocol all pref 1 \
        flower dst_mac 01:00:00:00:00:00/01:00:00:00:00:00 action pass \
        || { echo "ids-mirror: ERROR: failed to add multicast-exclude filter on $name ingress" >&2; exit 1; }
      tc filter add dev "$name" egress protocol all pref 1 \
        flower dst_mac 01:00:00:00:00:00/01:00:00:00:00:00 action pass \
        || { echo "ids-mirror: ERROR: failed to add multicast-exclude filter on $name egress" >&2; exit 1; }
      tc filter add dev "$name" ingress protocol arp pref 2 flower action pass \
        || { echo "ids-mirror: ERROR: failed to add ARP-exclude filter on $name ingress" >&2; exit 1; }
      tc filter add dev "$name" egress protocol arp pref 2 flower action pass \
        || { echo "ids-mirror: ERROR: failed to add ARP-exclude filter on $name egress" >&2; exit 1; }
      tc filter add dev "$name" ingress protocol ip pref 3 flower ip_proto icmp action pass \
        || { echo "ids-mirror: ERROR: failed to add ICMP-exclude filter on $name ingress" >&2; exit 1; }
      tc filter add dev "$name" egress protocol ip pref 3 flower ip_proto icmp action pass \
        || { echo "ids-mirror: ERROR: failed to add ICMP-exclude filter on $name egress" >&2; exit 1; }
      tc filter add dev "$name" ingress protocol ip pref 3 flower ip_proto udp dst_port 123 action pass \
        || { echo "ids-mirror: ERROR: failed to add NTP-exclude filter on $name ingress" >&2; exit 1; }
      tc filter add dev "$name" egress protocol ip pref 3 flower ip_proto udp dst_port 123 action pass \
        || { echo "ids-mirror: ERROR: failed to add NTP-exclude filter on $name egress" >&2; exit 1; }
      tc filter add dev "$name" ingress protocol ip pref 3 flower ip_proto udp src_port 123 action pass \
        || { echo "ids-mirror: ERROR: failed to add NTP-exclude filter (src) on $name ingress" >&2; exit 1; }
      tc filter add dev "$name" egress protocol ip pref 3 flower ip_proto udp src_port 123 action pass \
        || { echo "ids-mirror: ERROR: failed to add NTP-exclude filter (src) on $name egress" >&2; exit 1; }
      tc filter add dev "$name" ingress protocol ipv6 pref 4 flower action pass \
        || { echo "ids-mirror: ERROR: failed to add IPv6-exclude filter on $name ingress" >&2; exit 1; }
      tc filter add dev "$name" egress protocol ipv6 pref 4 flower action pass \
        || { echo "ids-mirror: ERROR: failed to add IPv6-exclude filter on $name egress" >&2; exit 1; }
      tc filter add dev "$name" ingress protocol all pref 10 \
        matchall action mirred egress mirror dev mirror \
        || { echo "ids-mirror: ERROR: failed to add ingress filter on $name" >&2; exit 1; }
      tc filter add dev "$name" egress protocol all pref 10 \
        matchall action mirred egress mirror dev mirror \
        || { echo "ids-mirror: ERROR: failed to add egress filter on $name" >&2; exit 1; }
      echo "ids-mirror: now mirroring $name -> mirror"
    '';
  };

  mirrorStopScript = pkgs.writeShellApplication {
    name = "ids-mirror-stop";
    runtimeInputs = [ pkgs.iproute2 ];
    text = ''
      tc_try() { "$@" 2>&1 || true; }

      ${lib.optionalString cfg.sender.mirrorExternalInterfaces ''
        for sysfs in /sys/class/net/*; do
          name=$(basename "$sysfs")
          [ -e "$sysfs/device" ] || continue
          [[ "$name" == "mirror" ]] && continue
          driver=$(basename "$(readlink "$sysfs/device/driver")" 2>/dev/null) || true
          [ "$driver" = "virtio_net" ] && continue
          tc_try tc filter del dev "$name" ingress
          tc_try tc filter del dev "$name" egress
          tc_try tc qdisc  del dev "$name" clsact
          echo "ids-mirror: removed tc rules from $name"
        done
      ''}

      ${lib.optionalString (cfg.sender.snaplen != null) ''
        tc_try tc filter del dev mirror egress
        tc_try tc qdisc del dev mirror clsact
      ''}

      tc_try tc qdisc del dev mirror root
      echo "ids-mirror: teardown complete"
    '';
  };
in
{
  _file = ./traffic-mirror.nix;

  options.ghaf.virtualization.microvm.trafficMirror = {
    sender = {
      enable = lib.mkEnableOption "L2 traffic mirror sender (this VM mirrors traffic to ids-vm)";
      mirrorExternalInterfaces = lib.mkEnableOption "mirror external (physical NIC) traffic";
      snaplen = lib.mkOption {
        type = lib.types.nullOr lib.types.ints.positive;
        default = null;
        example = 128;
        description = ''
          Truncate mirrored packets to this many bytes (header-only capture)
          via an eBPF classifier on the `mirror` tap's egress. null (default)
          mirrors full packets, unchanged.
        '';
      };
      rps = {
        enable = lib.mkEnableOption "RPS steering across mirrored external interfaces" // {
          default = true;
        };
      };
      netem = lib.mkOption {
        type = lib.types.str;
        default = "slot 10ms 20ms packets 300 limit 2000";
        example = "slot 2ms 3.7ms packets 250 limit 2000";
        description = ''
          netem qdisc params applied to the `mirror` tap, batching packets per
          slot to amortize virtio doorbell notifications (see the comment
          above where this is used). The right burst size is tied to the
          target's virtio-net ring size (commonly 256 for a plain tap
          backend - `ethtool -g mirror` shows the actual max) and to how the
          target's physical/USB interfaces behave under load - a value
          validated safe on one device/interface is not guaranteed safe on
          another. Override per device profile rather than relying on this
          default across targets.
        '';
      };
    };
    receiver = {
      enable = lib.mkEnableOption "L2 traffic mirror receiver (IDS-VM side)";
    };
  };

  config = lib.mkMerge [
    # Sender: mirrors physical NIC traffic via tap to the host relay
    (lib.mkIf cfg.sender.enable {

      boot.kernelPatches = [
        {
          name = "tc-mirror-support";
          patch = null;
          structuredExtraConfig =
            with lib.kernel;
            {
              NET_CLS_U32 = module;
              NET_CLS_FLOWER = module;
              NET_CLS_MATCHALL = module;
              NET_ACT_MIRRED = module;
              NET_ACT_SAMPLE = module;
              PSAMPLE = module;
              NET_SCH_INGRESS = module;
              NET_CLS_BPF = module;
              BPF_SYSCALL = yes;
            }
            // lib.optionalAttrs (cfg.sender.snaplen != null) {

            };
        }
      ];

      boot.kernelModules = [
        "cls_u32"
        "cls_flower"
        "cls_matchall"
        "act_mirred"
        "act_sample"
        "psample"
        "sch_ingress"
        "cls_bpf"
      ];

      microvm.interfaces = [
        {
          type = "tap";
          id = hostTapId;
          mac = mirrorSenderMac;
        }
      ];

      systemd.network = {
        links."20-mirror" = {
          matchConfig.PermanentMACAddress = mirrorSenderMac;
          linkConfig = {
            Name = "mirror";
            MTUBytes = "9000";
          };
        };
        networks."20-mirror" = {
          matchConfig.Name = "mirror";
          networkConfig = {
            LinkLocalAddressing = "no";
            DHCP = "no";
            IPv6AcceptRA = "no";
          };
          linkConfig = {
            ActivationPolicy = "always-up";
            RequiredForOnline = "no";
          };
        };
      };

      environment.systemPackages = lib.mkIf config.ghaf.profiles.debug.enable [
        idsMirrorBench
        pkgs.bpftools
        pkgs.iperf3
      ];
      networking.networkmanager.unmanaged = [ "mirror" ];

      # Compiled truncate object at a well-known path so ids-mirror-bench can
      # attach/detach it directly (`--truncation on|off`) without needing a
      # rebuild to change snaplen's on/off state at runtime.
      environment.etc = lib.mkIf (cfg.sender.snaplen != null) {
        "ids-mirror/trunc.o".source = mirrorTruncObj;
      };

      # Not started at boot - single balancing pass, manually triggered:
      # `systemctl start irqbalance`. Mirrors the same on-demand pattern set
      # up on the host (see host/traffic-mirror.nix).
      systemd.services.irqbalance = {
        description = "IRQ balancing: single pass (manual start only)";
        serviceConfig = {
          Type = "oneshot";
          ExecStart = "${pkgs.irqbalance}/bin/irqbalance --oneshot --debug --foreground";
        };
      };

      services.udev.extraRules = ''
        SUBSYSTEM=="net", ACTION=="add", DRIVERS=="usb", \
          RUN+="${pkgs.systemd}/bin/systemctl start --no-block ids-mirror-usb@${config.ghaf.common.hardware.usbEthernetPrefix}%E{IFINDEX}.service"
      '';

      systemd.services."ids-mirror-usb@" = {
        description = "Mirror hotplugged USB NIC %i to IDS-VM";
        after = [
          "ids-mirror.service"
          "sys-subsystem-net-devices-%i.device"
        ];
        serviceConfig = {
          Type = "oneshot";
          ExecStart = "${lib.getExe mirrorHotplugScript} %i";
        };
      };

      systemd.services."ids-mirror" = {
        description = "Mirror physical NIC traffic to IDS-VM via tap relay";
        after = [
          "network-online.target"
          "sys-subsystem-net-devices-mirror.device"
        ];
        bindsTo = [ "network-online.target" ];
        wantedBy = [ "network-online.target" ];
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
          Restart = "on-failure";
          RestartSec = "5s";
          ExecStart = lib.getExe mirrorStartScript;
          ExecStop = lib.getExe mirrorStopScript;
        };
      };
    })

    # Receiver: IDS-VM accepts mirrored traffic on mirror interface
    (lib.mkIf cfg.receiver.enable {

      microvm.interfaces = [
        {
          type = "tap";
          id = hostTapId;
          mac = mirrorReceiverMac;
        }
      ];

      systemd.network = {
        links."20-mirror" = {
          matchConfig.PermanentMACAddress = mirrorReceiverMac;
          linkConfig = {
            Name = "mirror";
            MTUBytes = "9000";
          };
        };
        networks."20-mirror" = {
          matchConfig.Name = "mirror";
          networkConfig = {
            LinkLocalAddressing = "no";
            DHCP = "no";
            IPv6AcceptRA = "no";
          };
          linkConfig = {
            ActivationPolicy = "always-up";
            RequiredForOnline = "no";
            Promiscuous = true;
          };
        };
      };

      networking.networkmanager.unmanaged = [ "mirror" ];
    })

  ];
}
