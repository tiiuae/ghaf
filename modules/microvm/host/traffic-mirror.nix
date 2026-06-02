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

  internalMirrorStartCmds = lib.concatMapStringsSep "\n" (vmName: ''
    ${pkgs.iproute2}/bin/tc qdisc del dev ${intTapFor vmName} clsact 2>/dev/null || true
    ${pkgs.iproute2}/bin/tc qdisc add dev ${intTapFor vmName} clsact
    ${pkgs.iproute2}/bin/tc filter add dev ${intTapFor vmName} ingress protocol all \
      matchall action mirred egress mirror dev ${inTap}
  '') internalTapVms;

  internalMirrorStopCmds = lib.concatMapStringsSep "\n" (vmName: ''
    ${pkgs.iproute2}/bin/tc filter del dev ${intTapFor vmName} ingress 2>/dev/null || true
    ${pkgs.iproute2}/bin/tc qdisc  del dev ${intTapFor vmName} clsact  2>/dev/null || true
  '') internalTapVms;

  # tc relayMethod: per-packet tc filter/mirred redirect on each sender tap.
  relayStartCmds = lib.concatMapStringsSep "\n" (vmName: ''
    ${pkgs.iproute2}/bin/tc qdisc del dev ${tapFor vmName} clsact 2>/dev/null || true
    ${pkgs.iproute2}/bin/tc qdisc add dev ${tapFor vmName} clsact
    ${pkgs.iproute2}/bin/tc filter add dev ${tapFor vmName} ingress protocol all \
      matchall action mirred egress redirect dev ${inTap}
  '') senderNames;

  relayStopCmds = lib.concatMapStringsSep "\n" (vmName: ''
    ${pkgs.iproute2}/bin/tc filter del dev ${tapFor vmName} ingress 2>/dev/null || true
    ${pkgs.iproute2}/bin/tc qdisc del dev ${tapFor vmName} clsact 2>/dev/null || true
  '') senderNames;

  # RPS on each sender's host-side receive tap (mir-<vmName>) - this is the
  # RX-heavy end of the relay (receives whatever the sender VM's own
  # mirror-tx tap sends), unlike the sender-side taps which are TX-only and
  # use XPS instead. Spreads across CPU2-4, skipping CPU0-1 which are left
  # for other host work - only bothers if the host actually has the CPUs to
  # spare (>=5, so CPU4 exists). Best-effort per queue: harmless if a given
  # tap has fewer than 3 queues.
  rpsStartCmds = lib.concatMapStringsSep "\n" (vmName: ''
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
    # writeShellScript has no `set -e`, so the script's own exit status is
    # whatever the last command returned - without this, an `if` whose
    # condition is false (e.g. nproc<5, intentionally skipping RPS setup)
    # would make the script exit 1 and systemd report a spurious failure.
    true
  '') senderNames;

  # bridge relayMethod: sender taps join br-mirror as isolated ports - they
  # can only reach a non-isolated port (the receiver tap below), never each
  # other.
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

      # Not started at boot - its actual usefulness here is unverified
      # (host-level irqbalance can't reach the guest-internal NIC IRQs this
      # feature's tuning targets). No `wantedBy`, so it only runs when
      # explicitly started: `systemctl start irqbalance`. --oneshot does a
      # single balancing pass and exits, matching Type=oneshot, instead of
      # lingering as a background daemon during measurement windows.
      systemd.services.irqbalance = {
        description = "IRQ balancing: single pass (manual start only)";
        serviceConfig = {
          Type = "oneshot";
          ExecStart = "${pkgs.irqbalance}/bin/irqbalance --oneshot --debug --foreground";
        };
      };

      boot.kernelPatches = [
        {
          name = "tc-mirror-support";
          patch = null;
          structuredExtraConfig = with lib.kernel; {
            # NET_CLS_U32/NET_ACT_MIRRED/NET_SCH_INGRESS are needed for
            # ids-internal-mirror (VM-to-VM tap mirroring) regardless of
            # relayMethod, and for the sender->receiver relay itself when
            # relayMethod = "tc". BRIDGE is only needed when relayMethod =
            # "bridge", but harmless to always include.
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

      systemd.services."ids-bench-server" = lib.mkIf config.ghaf.profiles.debug.enable {
        description = "IDS benchmark command listener (listens on port 9999)";
        wantedBy = [ "multi-user.target" ];
        serviceConfig = {
          Type = "simple";
          ExecStart = "${pkgs.ids-mirror-bench}/bin/ids-bench-server";
          Restart = "always";
          RestartSec = "1s";
        };
      };

      ghaf.firewall.allowedTCPPorts = lib.optionals config.ghaf.profiles.debug.enable [ 9999 ];

      systemd.services."ids-internal-mirror" =
        lib.mkIf (config.ghaf.global-config.idsvm.passiveMonitor.internal or false)
          {
            description = "IDS internal mirror: copy inter-VM tap traffic to ${cfg.receiverVm}";
            wantedBy = [ "multi-user.target" ];
            after = (map (n: "microvm@${n}.service") internalTapVms) ++ [ "microvm@${cfg.receiverVm}.service" ];
            bindsTo = [ "microvm@${cfg.receiverVm}.service" ];
            serviceConfig = {
              Type = "oneshot";
              RemainAfterExit = true;
              ExecStart = pkgs.writeShellScript "ids-internal-mirror-start" internalMirrorStartCmds;
              ExecStop = pkgs.writeShellScript "ids-internal-mirror-stop" internalMirrorStopCmds;
            };
          };

      systemd.services."ids-mirror-rps" = lib.mkIf cfg.rps.enable {
        description = "RPS steering for sender VMs' host-side receive taps";
        wantedBy = [ "multi-user.target" ];
        after = map (n: "microvm@${n}.service") senderNames;
        bindsTo = map (n: "microvm@${n}.service") senderNames;
        # BindsTo only guarantees this stops when the sender VM's service
        # stops - it doesn't retrigger this when that service starts again
        # (e.g. after a VM restart recreates mir-<vmName>, resetting the
        # masks to 0). PartOf propagates restarts too, so RPS gets reapplied
        # whenever the sender VM does.
        partOf = map (n: "microvm@${n}.service") senderNames;
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
          ExecStart = pkgs.writeShellScript "ids-mirror-rps-start" rpsStartCmds;
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
          ExecStart = pkgs.writeShellScript "ids-tap-relay-start" relayStartCmds;
          ExecStop = pkgs.writeShellScript "ids-tap-relay-stop" relayStopCmds;
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
          # Disable STP, same reasoning as the host's virbr0 (see
          # modules/microvm/host/networking.nix): static topology, no loops,
          # and STP's forward-delay would just add pointless startup latency.
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
