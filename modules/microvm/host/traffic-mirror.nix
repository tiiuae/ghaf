# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# Host-side IDS traffic mirror relay
#
# Relays sender VMs' mirror taps to the receiver VM (ids-vm)'s tap, using
# either method (see relayMethod):
#   bridge - sender taps join a Linux bridge as "isolated" ports, so traffic
#            only ever flows sender->receiver (kernel bridging fast path,
#            never sender<->sender or receiver->sender).
#   tc     - the original per-packet tc filter/mirred redirect.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.ghaf.virtualization.microvm.host.trafficMirror;

  tapFor = vmName: "mir-${vmName}";
  intTapFor = vmName: "${config.ghaf.networking.vmTapPrefix}-${vmName}";

  # Collect all VMs that have sender.enable = true in their NixOS config.
  senderVms = lib.filterAttrs (
    _vmName: vm:
    (vm.evaluatedConfig != null)
    && (vm.evaluatedConfig.config.ghaf.virtualization.microvm.trafficMirror.sender.enable or false)
  ) config.microvm.vms;

  senderNames = lib.attrNames senderVms;

  # All VMs with an internal tap, excluding the receiver itself
  internalTapVms = lib.filter (n: n != cfg.receiverVm) (lib.attrNames config.microvm.vms);

  inTap = tapFor cfg.receiverVm;
  bridgeIface = "br-mirror";

  # Start/stop scripts steering each dev's ingress into the receiver tap via tc mirred.
  mkTcSteer =
    name: action: devs:
    let
      script =
        suffix: perDev:
        pkgs.writeShellApplication {
          name = "${name}-${suffix}";
          runtimeInputs = [ pkgs.iproute2 ];
          text = lib.concatMapStringsSep "\n" perDev devs;
        };
    in
    {
      start = script "start" (dev: ''
        tc qdisc del dev ${dev} clsact 2>/dev/null || true
        tc qdisc add dev ${dev} clsact
        tc filter add dev ${dev} ingress protocol all \
          matchall action mirred egress ${action} dev ${inTap}
      '');
      stop = script "stop" (dev: ''
        tc filter del dev ${dev} ingress 2>/dev/null || true
        tc qdisc del dev ${dev} clsact 2>/dev/null || true
      '');
    };

  internalMirror = mkTcSteer "ids-internal-mirror" "mirror" (map intTapFor internalTapVms);

  # tc relayMethod: per-packet tc filter/mirred redirect on each sender tap.
  relay = mkTcSteer "ids-tap-relay" "redirect" (map tapFor senderNames);

  # RPS on the RX-heavy host-side tap (mir-<vmName>) across CPU2-4, leaving
  # CPU0-1 free; skipped below 5 CPUs. Best-effort per queue.
  rpsStart = pkgs.writeShellApplication {
    name = "ids-mirror-rps-start";
    text = lib.concatMapStringsSep "\n" (vmName: ''
      tap="${tapFor vmName}"
      if [ "$(nproc)" -ge 5 ]; then
        for q in 0 1 2; do
          case "$q" in
            0) mask=4 ;;
            1) mask=8 ;;
            2) mask=10 ;;
          esac
          f="/sys/class/net/$tap/queues/rx-$q/rps_cpus"
          fc="/sys/class/net/$tap/queues/rx-$q/rps_flow_cnt"
          [ -e "$f" ] && { echo "$mask" > "$f" 2>/dev/null || true; }
          [ -e "$fc" ] && { echo 32768 > "$fc" 2>/dev/null || true; }
        done
      fi
      # Exit 0 whichever branch ran: a missing queue file leaves the last
      # `[ -e ] &&` at status 1, which would fail the oneshot.
      true
    '') senderNames;
  };

  # bridge relayMethod: isolated ports can only reach the receiver tap, never each other.
  senderTapNetworks = lib.listToAttrs (
    map (vmName: {
      name = "09-${tapFor vmName}";
      value = {
        matchConfig.Name = tapFor vmName;
        networkConfig = {
          LinkLocalAddressing = "no";
          Bridge = bridgeIface;
        };
        bridgeConfig = {
          Isolated = true;
          Learning = false;
        };
        linkConfig = {
          ActivationPolicy = "always-up";
          RequiredForOnline = "no";
        };
      };
    }) senderNames
  );
in
{
  _file = ./traffic-mirror.nix;

  options.ghaf.virtualization.microvm.host.trafficMirror = {
    enable = lib.mkEnableOption "Host-side tap relay from sender VMs to ids-vm";

    relayMethod = lib.mkOption {
      type = lib.types.enum [
        "bridge"
        "tc"
      ];
      default = "bridge";
      description = ''
        How to relay sender VMs' mirror taps to the receiver tap:
        - "bridge": Linux bridge with isolated sender ports (kernel's native
          bridging fast path).
        - "tc": per-packet tc filter/mirred redirect (the original method).
      '';
    };

    receiverVm = lib.mkOption {
      type = lib.types.str;
      default = "ids-vm";
      description = "Name of the VM that receives all mirrored traffic.";
    };

    rps = {
      enable = lib.mkEnableOption "RPS steering on sender VMs' host-side receive taps" // {
        default = true;
      };
    };
  };

  config = lib.mkMerge [
    (lib.mkIf cfg.enable {

      boot.kernelPatches = [
        {
          name = "tc-mirror-support";
          patch = null;
          structuredExtraConfig = with lib.kernel; {
            # U32/MIRRED/INGRESS serve ids-internal-mirror and relayMethod = "tc";
            # BRIDGE only relayMethod = "bridge", but is harmless to always include.
            NET_CLS_U32 = module;
            NET_CLS_MATCHALL = module;
            NET_ACT_MIRRED = module;
            NET_SCH_INGRESS = module;
            BRIDGE = module;
          };
        }
      ];

      boot.kernelModules = [
        "cls_u32"
        "cls_matchall"
        "act_mirred"
        "sch_ingress"
        "bridge"
      ];

      ghaf.firewall.allowedTCPPorts = lib.optionals config.ghaf.profiles.debug.enable [ 9999 ];

      systemd.services = {
        # Manual only (`systemctl start irqbalance`): usefulness is unverified,
        # as host irqbalance can't reach guest NIC IRQs. --oneshot does one pass.
        irqbalance = {
          description = "IRQ balancing: single pass (manual start only)";
          serviceConfig = {
            Type = "oneshot";
            ExecStart = "${pkgs.irqbalance}/bin/irqbalance --oneshot --debug --foreground";
          };
        };

        "ids-bench-server" = lib.mkIf config.ghaf.profiles.debug.enable {
          description = "IDS benchmark command listener (listens on port 9999)";
          wantedBy = [ "multi-user.target" ];
          serviceConfig = {
            Type = "simple";
            ExecStart = "${pkgs.ids-mirror-bench}/bin/ids-bench-server";
            Restart = "always";
            RestartSec = "1s";
          };
        };

        "ids-internal-mirror" =
          lib.mkIf (config.ghaf.global-config.idsvm.passiveMonitor.internal or false)
            {
              description = "IDS internal mirror: copy inter-VM tap traffic to ${cfg.receiverVm}";
              wantedBy = [ "multi-user.target" ];
              after = (map (n: "microvm@${n}.service") internalTapVms) ++ [ "microvm@${cfg.receiverVm}.service" ];
              bindsTo = [ "microvm@${cfg.receiverVm}.service" ];
              serviceConfig = {
                Type = "oneshot";
                RemainAfterExit = true;
                ExecStart = lib.getExe internalMirror.start;
                ExecStop = lib.getExe internalMirror.stop;
              };
            };

        "ids-mirror-rps" = lib.mkIf cfg.rps.enable {
          description = "RPS steering for sender VMs' host-side receive taps";
          wantedBy = [ "multi-user.target" ];
          after = map (n: "microvm@${n}.service") senderNames;
          bindsTo = map (n: "microvm@${n}.service") senderNames;
          # BindsTo doesn't re-run this after a VM restart recreates mir-<vmName>
          # (masks reset to 0); PartOf propagates restarts so RPS is reapplied.
          partOf = map (n: "microvm@${n}.service") senderNames;
          serviceConfig = {
            Type = "oneshot";
            RemainAfterExit = true;
            ExecStart = lib.getExe rpsStart;
          };
        };
      };
    })
    (lib.mkIf (cfg.enable && cfg.relayMethod == "tc") {
      systemd.services."ids-tap-relay" = {
        description = "IDS tap relay: redirect mirror traffic to ${cfg.receiverVm}";
        wantedBy = [ "multi-user.target" ];
        bindsTo = (map (n: "microvm@${n}.service") senderNames) ++ [ "microvm@${cfg.receiverVm}.service" ];
        after = (map (n: "microvm@${n}.service") senderNames) ++ [ "microvm@${cfg.receiverVm}.service" ];
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
          ExecStart = lib.getExe relay.start;
          ExecStop = lib.getExe relay.stop;
        };
      };

      systemd.network.networks =
        lib.listToAttrs (
          map (vmName: {
            name = "09-${tapFor vmName}";
            value = {
              matchConfig.Name = tapFor vmName;
              networkConfig.LinkLocalAddressing = "no";
              linkConfig = {
                ActivationPolicy = "always-up";
                RequiredForOnline = "no";
              };
            };
          }) senderNames
        )
        // {
          "09-${inTap}" = {
            matchConfig.Name = inTap;
            networkConfig.LinkLocalAddressing = "no";
            linkConfig = {
              ActivationPolicy = "always-up";
              RequiredForOnline = "no";
            };
          };
        };
    })
    (lib.mkIf (cfg.enable && cfg.relayMethod == "bridge") {
      systemd.network = {
        netdevs."09-${bridgeIface}" = {
          netdevConfig = {
            Kind = "bridge";
            Name = bridgeIface;
          };
          # No STP (as virbr0, see networking.nix): static topology, and its
          # forward-delay only adds startup latency.
          bridgeConfig = {
            STP = false;
            ForwardDelaySec = 0;
          };
        };

        networks = senderTapNetworks // {
          "09-${bridgeIface}" = {
            matchConfig.Name = bridgeIface;
            networkConfig.LinkLocalAddressing = "no";
            linkConfig = {
              ActivationPolicy = "always-up";
              RequiredForOnline = "no";
            };
          };
          # Receiver tap: normal (non-isolated) bridge port - the only one
          # sender taps are allowed to reach.
          "09-${inTap}" = {
            matchConfig.Name = inTap;
            networkConfig = {
              LinkLocalAddressing = "no";
              Bridge = bridgeIface;
            };
            linkConfig = {
              ActivationPolicy = "always-up";
              RequiredForOnline = "no";
            };
          };
        };
      };
    })
  ];
}
