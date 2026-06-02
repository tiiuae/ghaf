# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# Host-side IDS traffic mirror relay
#
# Redirects VMs tap traffic to the receiver VM (ids-vm) via TC mirred.
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

  relayStartCmds = lib.concatMapStringsSep "\n" (vmName: ''
    ${pkgs.iproute2}/bin/tc qdisc del dev ${tapFor vmName} clsact 2>/dev/null || true
    ${pkgs.iproute2}/bin/tc qdisc add dev ${tapFor vmName} clsact
    ${pkgs.iproute2}/bin/tc filter add dev ${tapFor vmName} ingress protocol all \
      u32 match u8 0 0 action mirred egress redirect dev ${inTap}
  '') senderNames;

  relayStopCmds = lib.concatMapStringsSep "\n" (vmName: ''
    ${pkgs.iproute2}/bin/tc filter del dev ${tapFor vmName} ingress 2>/dev/null || true
    ${pkgs.iproute2}/bin/tc qdisc del dev ${tapFor vmName} clsact 2>/dev/null || true
  '') senderNames;

  internalMirrorStartCmds = lib.concatMapStringsSep "\n" (vmName: ''
    ${pkgs.iproute2}/bin/tc qdisc del dev ${intTapFor vmName} clsact 2>/dev/null || true
    ${pkgs.iproute2}/bin/tc qdisc add dev ${intTapFor vmName} clsact
    ${pkgs.iproute2}/bin/tc filter add dev ${intTapFor vmName} ingress protocol all \
      u32 match u8 0 0 action mirred egress mirror dev ${inTap}
  '') internalTapVms;

  internalMirrorStopCmds = lib.concatMapStringsSep "\n" (vmName: ''
    ${pkgs.iproute2}/bin/tc filter del dev ${intTapFor vmName} ingress 2>/dev/null || true
    ${pkgs.iproute2}/bin/tc qdisc  del dev ${intTapFor vmName} clsact  2>/dev/null || true
  '') internalTapVms;

  senderTapNetworks = lib.listToAttrs (
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
  );
in
{
  _file = ./traffic-mirror.nix;

  options.ghaf.virtualization.microvm.host.trafficMirror = {
    enable = lib.mkEnableOption "Host-side tap relay (TC redirect from sender VMs to ids-vm)";

    receiverVm = lib.mkOption {
      type = lib.types.str;
      default = "ids-vm";
      description = "Name of the VM that receives all mirrored traffic.";
    };
  };

  config = lib.mkIf cfg.enable {
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

    systemd.network.networks = senderTapNetworks // {
      "09-${inTap}" = {
        matchConfig.Name = inTap;
        networkConfig.LinkLocalAddressing = "no";
        linkConfig = {
          ActivationPolicy = "always-up";
          RequiredForOnline = "no";
        };
      };
    };
  };
}
