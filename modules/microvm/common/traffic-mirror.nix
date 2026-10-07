# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# L2 Traffic Mirror Module for IDS-VM
#
# Provides two roles:
#   sender   — mirrors physical NIC traffic to a tap (tap-mirror-<hostname>)
#   receiver — IDS-VM side: receives mirrored frames on the mirror interface
#
# The host relays frames between sender and receiver taps (bridge or tc,
# see host/traffic-mirror.nix relayMethod)
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.ghaf.virtualization.microvm.trafficMirror;

  hostTapId = "mir-${config.networking.hostName}";

  # eBPF classifier truncating mirrored frames to cfg.sender.snaplen bytes, on
  # the `mirror` tap's egress: past the mirred clone, so live traffic is untouched.
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
        # cc-wrapper's hardening flags are rejected by clang for -target bpf;
        # the BPF verifier is the real safety net.
        hardeningDisable = [ "all" ];
      }
      ''
        clang -O2 -target bpf -idirafter ${pkgs.linuxHeaders}/include \
          -c ${mirrorTruncSrc} -o $out
      '';

  # Shared by all three scripts below. No message prefix: systemd already tags
  # each line with the unit's own name in the journal.
  scriptPrelude = ''
    error() { echo "ERROR: $*" >&2; exit 1; }
    # tc cleanup that may legitimately fail -- the qdisc need not exist yet.
    tc_try() { "$@" 2>&1 || true; }
  '';

  mirrorStartScript = pkgs.writeShellApplication {
    name = "ids-mirror-start";
    runtimeInputs = [
      pkgs.iproute2
    ];
    text = ''
      ${scriptPrelude}
      # Accumulate mirrored packets in slots before sending to ids-vm.
      # virtio's xmit_more defers the doorbell write until the last packet in a burst.
      # This helps reduce CPU usage when mirroring high packet rates.
      tc_try tc qdisc del dev mirror root
      tc qdisc add dev mirror root netem ${cfg.sender.netem} \
        || error "failed to add netem qdisc on mirror"

      ${lib.optionalString (cfg.sender.snaplen != null) ''
        # Truncate to ${toString cfg.sender.snaplen} bytes on the tap's egress, before the netem
        # queue, so everything downstream handles header-only frames.
        tc_try tc filter del dev mirror egress
        tc_try tc qdisc del dev mirror clsact
        tc qdisc add dev mirror clsact \
          || error "failed to add clsact qdisc on mirror"
        tc filter add dev mirror egress bpf da obj ${mirrorTruncObj} sec classifier \
          || error "failed to add truncate filter on mirror"
      ''}

      ${lib.optionalString cfg.sender.mirrorExternalInterfaces ''
        mirrored=0

        ${lib.optionalString cfg.sender.rps.enable ''
          sysctl -w net.core.rps_sock_flow_entries=32768 >/dev/null 2>&1 || true
        ''}
        for sysfs in /sys/class/net/*; do
          name=$(basename "$sysfs")
          [ -e "$sysfs/device" ] || continue
          [[ "$name" == "mirror" ]] && continue
          driver=$(basename "$(readlink "$sysfs/device/driver")" 2>/dev/null) || true
          [ "$driver" = "virtio_net" ] && continue

          echo "mirroring external $name -> mirror"

          tc_try tc filter del dev "$name" ingress
          tc_try tc filter del dev "$name" egress
          tc_try tc qdisc  del dev "$name" clsact
          tc qdisc  add dev "$name" clsact \
            || error "failed to add clsact qdisc on $name"
          # Exclude low-value/high-volume traffic (DNS deliberately kept) before
          # the pref-10 catch-all, so it passes before mirred sees it.
          # Multicast/broadcast (incl. LLDP/CDP/STP): flower dst_mac, not u32 at 0 -
          # on egress u32 can land on the IP header, whose 0x45 first byte has the
          # multicast bit set and would misclassify ordinary IPv4.
          tc filter add dev "$name" ingress protocol all pref 1 \
            flower dst_mac 01:00:00:00:00:00/01:00:00:00:00:00 action pass \
            || error "failed to add multicast-exclude filter on $name ingress"
          tc filter add dev "$name" egress protocol all pref 1 \
            flower dst_mac 01:00:00:00:00:00/01:00:00:00:00:00 action pass \
            || error "failed to add multicast-exclude filter on $name egress"
          # ARP
          tc filter add dev "$name" ingress protocol arp pref 2 flower action pass \
            || error "failed to add ARP-exclude filter on $name ingress"
          tc filter add dev "$name" egress protocol arp pref 2 flower action pass \
            || error "failed to add ARP-exclude filter on $name egress"
          # ICMP + NTP (UDP/123, both directions) share one pref per direction:
          # flower hashes same-pref rules in a single lookup pass.
          tc filter add dev "$name" ingress protocol ip pref 3 flower ip_proto icmp action pass \
            || error "failed to add ICMP-exclude filter on $name ingress"
          tc filter add dev "$name" egress protocol ip pref 3 flower ip_proto icmp action pass \
            || error "failed to add ICMP-exclude filter on $name egress"
          tc filter add dev "$name" ingress protocol ip pref 3 flower ip_proto udp dst_port 123 action pass \
            || error "failed to add NTP-exclude filter on $name ingress"
          tc filter add dev "$name" egress protocol ip pref 3 flower ip_proto udp dst_port 123 action pass \
            || error "failed to add NTP-exclude filter on $name egress"
          tc filter add dev "$name" ingress protocol ip pref 3 flower ip_proto udp src_port 123 action pass \
            || error "failed to add NTP-exclude filter (src) on $name ingress"
          tc filter add dev "$name" egress protocol ip pref 3 flower ip_proto udp src_port 123 action pass \
            || error "failed to add NTP-exclude filter (src) on $name egress"
          # IPv6, excluded entirely (DNS over IPv4 is unaffected)
          tc filter add dev "$name" ingress protocol ipv6 pref 4 flower action pass \
            || error "failed to add IPv6-exclude filter on $name ingress"
          tc filter add dev "$name" egress protocol ipv6 pref 4 flower action pass \
            || error "failed to add IPv6-exclude filter on $name egress"
          # matchall instead of u32 match-all: skips u32's hash-dispatch setup
          # for a rule that unconditionally matches every remaining packet.
          tc filter add dev "$name" ingress protocol all pref 10 \
            matchall action mirred egress mirror dev mirror \
            || error "failed to add ingress filter on $name"
          tc filter add dev "$name" egress protocol all pref 10 \
            matchall action mirred egress mirror dev mirror \
            || error "failed to add egress filter on $name"

          ${lib.optionalString cfg.sender.rps.enable ''
            # RPS: one distinct CPU per interface, round-robin over nproc.
            rps_cpu=$((mirrored % $(nproc)))
            rps_mask=$(printf '%x' $((1 << rps_cpu)))
            rps_f="$sysfs/queues/rx-0/rps_cpus"
            rps_fc="$sysfs/queues/rx-0/rps_flow_cnt"
            if [ -e "$rps_f" ]; then
              echo "$rps_mask" > "$rps_f" 2>/dev/null || true
              [ -e "$rps_fc" ] && { echo 32768 > "$rps_fc" 2>/dev/null || true; }
              echo "rps on $name -> cpu$rps_cpu (mask=$rps_mask)"
            fi
          ''}

          mirrored=$((mirrored + 1))
        done
      ''}

      ${
        if cfg.sender.mirrorExternalInterfaces then
          ''
            [ "$mirrored" -gt 0 ] || error "mirrorExternalInterfaces is on but no eligible interfaces were found to mirror"
            echo "mirroring $mirrored interface(s) to mirror"
          ''
        else
          ''
            echo "mirrorExternalInterfaces is off - external interface mirroring not configured (internal-only monitoring, or netem/truncation setup only)"
          ''
      }
    '';
  };

  mirrorHotplugScript = pkgs.writeShellApplication {
    name = "ids-mirror-usb-hotplug";
    runtimeInputs = [ pkgs.iproute2 ];
    text = ''
      ${scriptPrelude}
      name="$1"
      [ -e "/sys/class/net/mirror" ] || { echo "mirror tap not ready, skipping $name" >&2; exit 0; }
      echo "hotplug $name -> mirror"
      tc_try tc filter del dev "$name" ingress
      tc_try tc filter del dev "$name" egress
      tc_try tc qdisc  del dev "$name" clsact
      tc qdisc  add dev "$name" clsact \
        || error "failed to add clsact qdisc on $name"
      tc filter add dev "$name" ingress protocol all pref 1 \
        flower dst_mac 01:00:00:00:00:00/01:00:00:00:00:00 action pass \
        || error "failed to add multicast-exclude filter on $name ingress"
      tc filter add dev "$name" egress protocol all pref 1 \
        flower dst_mac 01:00:00:00:00:00/01:00:00:00:00:00 action pass \
        || error "failed to add multicast-exclude filter on $name egress"
      tc filter add dev "$name" ingress protocol arp pref 2 flower action pass \
        || error "failed to add ARP-exclude filter on $name ingress"
      tc filter add dev "$name" egress protocol arp pref 2 flower action pass \
        || error "failed to add ARP-exclude filter on $name egress"
      tc filter add dev "$name" ingress protocol ip pref 3 flower ip_proto icmp action pass \
        || error "failed to add ICMP-exclude filter on $name ingress"
      tc filter add dev "$name" egress protocol ip pref 3 flower ip_proto icmp action pass \
        || error "failed to add ICMP-exclude filter on $name egress"
      tc filter add dev "$name" ingress protocol ip pref 3 flower ip_proto udp dst_port 123 action pass \
        || error "failed to add NTP-exclude filter on $name ingress"
      tc filter add dev "$name" egress protocol ip pref 3 flower ip_proto udp dst_port 123 action pass \
        || error "failed to add NTP-exclude filter on $name egress"
      tc filter add dev "$name" ingress protocol ip pref 3 flower ip_proto udp src_port 123 action pass \
        || error "failed to add NTP-exclude filter (src) on $name ingress"
      tc filter add dev "$name" egress protocol ip pref 3 flower ip_proto udp src_port 123 action pass \
        || error "failed to add NTP-exclude filter (src) on $name egress"
      tc filter add dev "$name" ingress protocol ipv6 pref 4 flower action pass \
        || error "failed to add IPv6-exclude filter on $name ingress"
      tc filter add dev "$name" egress protocol ipv6 pref 4 flower action pass \
        || error "failed to add IPv6-exclude filter on $name egress"
      tc filter add dev "$name" ingress protocol all pref 10 \
        matchall action mirred egress mirror dev mirror \
        || error "failed to add ingress filter on $name"
      tc filter add dev "$name" egress protocol all pref 10 \
        matchall action mirred egress mirror dev mirror \
        || error "failed to add egress filter on $name"
      echo "now mirroring $name -> mirror"
    '';
  };

  mirrorStopScript = pkgs.writeShellApplication {
    name = "ids-mirror-stop";
    runtimeInputs = [ pkgs.iproute2 ];
    text = ''
      ${scriptPrelude}
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
          echo "removed tc rules from $name"
        done
      ''}

      ${lib.optionalString (cfg.sender.snaplen != null) ''
        tc_try tc filter del dev mirror egress
        tc_try tc qdisc del dev mirror clsact
      ''}

      tc_try tc qdisc del dev mirror root
      echo "teardown complete"
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
          Truncate mirrored packets to this many bytes, capturing headers
          only. An eBPF classifier on the `mirror` tap's egress does the
          truncation.

          Leave as null to mirror whole packets without truncation.
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
          netem qdisc parameters applied to the `mirror` tap. Batching
          packets per slot amortizes the virtio doorbell notifications.

          The right burst size depends on the target. It is tied to the
          virtio-net ring size. It also depends on how the target's
          physical and USB interfaces behave under load.
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
      # tc mirred cloning physical NIC traffic is extra work on top of the
      # VM's existing role; force a core for it over the plain default.
      microvm.vcpu = lib.mkForce 3;

      boot = {
        kernelPatches = [
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
              }
              // lib.optionalAttrs (cfg.sender.snaplen != null) {
                NET_CLS_BPF = module;
                BPF_SYSCALL = yes;
              };
          }
        ];

        kernelModules = [
          "cls_u32"
          "cls_flower"
          "cls_matchall"
          "act_mirred"
          "act_sample"
          "psample"
          "sch_ingress"
        ]
        ++ lib.optional (cfg.sender.snaplen != null) "cls_bpf";
      };

      # Mirror interface MAC
      ghaf.networking.reservedMacs.ids-mirror-sender = "02:AD:00:00:FF:01";

      microvm.interfaces = [
        {
          type = "tap";
          id = hostTapId;
          mac = config.ghaf.networking.reservedMacs.ids-mirror-sender;
        }
      ];

      systemd.network = {
        links."20-mirror" = {
          matchConfig.PermanentMACAddress = config.ghaf.networking.reservedMacs.ids-mirror-sender;
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
        pkgs.ids-mirror-bench
        pkgs.bpftools
        pkgs.iperf3
      ];

      networking.networkmanager.unmanaged = [ "mirror" ];

      # Well-known path so ids-mirror-bench can attach/detach it (`--truncation on|off`).
      environment.etc = lib.mkIf (cfg.sender.snaplen != null) {
        "ids-mirror/trunc.o".source = mirrorTruncObj;
      };

      services.udev.extraRules = ''
        SUBSYSTEM=="net", ACTION=="add", DRIVERS=="usb", \
          RUN+="${pkgs.systemd}/bin/systemctl start --no-block ids-mirror-usb@${config.ghaf.common.hardware.usbEthernetPrefix}%E{IFINDEX}.service"
      '';

      systemd.services = {
        irqbalance = {
          description = "IRQ balancing: single pass (manual start only)";
          serviceConfig = {
            Type = "oneshot";
            ExecStart = "${pkgs.irqbalance}/bin/irqbalance --oneshot --debug --foreground";
          };
        };

        "ids-mirror-usb@" = {
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

        "ids-mirror" = {
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
      };
    })

    # Receiver: IDS-VM accepts mirrored traffic on mirror interface
    (lib.mkIf cfg.receiver.enable {
      assertions = [
        {
          assertion = !config.ghaf.virtualization.microvm.vm-networking.isGateway;
          message = ''
            trafficMirror.receiver.enable makes this VM a copy destination for
            mirrored frames, but vm-networking.isGateway is true, which turns on
            ip_forward and NAT and puts it inline on live traffic instead.
          '';
        }
      ];

      # Mirror interface MAC
      ghaf.networking.reservedMacs.ids-mirror-receiver = "02:AD:00:00:FF:02";

      microvm.interfaces = [
        {
          type = "tap";
          id = hostTapId;
          mac = config.ghaf.networking.reservedMacs.ids-mirror-receiver;
        }
      ];

      systemd.network = {
        links."20-mirror" = {
          matchConfig.PermanentMACAddress = config.ghaf.networking.reservedMacs.ids-mirror-receiver;
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
