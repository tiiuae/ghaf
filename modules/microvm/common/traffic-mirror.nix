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
      tc qdisc add dev mirror root netem slot 30ms 50ms packets 1024 limit 4096 \
        || { echo "ids-mirror: ERROR: failed to add netem qdisc on mirror" >&2; exit 1; }

      mirrored=0

      ${lib.optionalString cfg.sender.mirrorExternalInterfaces ''
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
          tc filter add dev "$name" ingress protocol all \
            u32 match u8 0 0 action mirred egress mirror dev mirror \
            || { echo "ids-mirror: ERROR: failed to add ingress filter on $name" >&2; exit 1; }
          tc filter add dev "$name" egress protocol all \
            u32 match u8 0 0 action mirred egress mirror dev mirror \
            || { echo "ids-mirror: ERROR: failed to add egress filter on $name" >&2; exit 1; }
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
      tc filter add dev "$name" ingress protocol all \
        u32 match u8 0 0 action mirred egress mirror dev mirror \
        || { echo "ids-mirror: ERROR: failed to add ingress filter on $name" >&2; exit 1; }
      tc filter add dev "$name" egress protocol all \
        u32 match u8 0 0 action mirred egress mirror dev mirror \
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
    };
    receiver = {
      enable = lib.mkEnableOption "L2 traffic mirror receiver (IDS-VM side)";
    };
  };

  config = lib.mkMerge [
    # Sender: mirrors physical NIC traffic via tap to the host relay
    (lib.mkIf cfg.sender.enable {

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

      environment.systemPackages = lib.mkIf config.ghaf.profiles.debug.enable [ idsMirrorBench ];

      networking.networkmanager.unmanaged = [ "mirror" ];

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
