# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  config,
  lib,
  pkgs,
  ...
}:
let
  deadlineSec = 30;
  cliArgs = lib.replaceStrings [ "/run" ] [ "/etc" ] config.ghaf.givc.cliArgs;
  mgbe0 = config.ghaf.hardware.nvidia.passthroughs.mgbe0_net_vm.enable;
  crosvmVms = lib.filterAttrs (
    _: vm: (lib.ghaf.vm.getConfig vm).microvm.hypervisor == "crosvm"
  ) config.microvm.vms;
  guestService =
    name: vm:
    let
      vmConfig = lib.ghaf.vm.getConfig vm;
      services = vmConfig.givc.sysvm.capabilities.services or [ ];
    in
    if mgbe0 && name == "net-vm" then
      "ghaf-mgbe0-poweroff.service"
    else if vmConfig.ghaf.type == "app-vm" || lib.elem "ghaf-crosvm-poweroff.service" services then
      "ghaf-crosvm-poweroff.service"
    else
      "poweroff.target";
  mkStopScript =
    name: vm: service:
    let
      vmConfig = lib.ghaf.vm.getConfig vm;
      crosvm = lib.getExe vmConfig.microvm.crosvm.package;
      socket = "${config.microvm.stateDir}/${name}/${vmConfig.microvm.socket}";
    in
    pkgs.writeShellScript "stop-crosvm-${name}" ''
      set -u
      unit=${lib.escapeShellArg "microvm@${name}.service"}
      pid=$(${lib.getExe' pkgs.systemd "systemctl"} show -p MainPID --value "$unit")
      [ -n "$pid" ] && [ "$pid" != 0 ] || exit 0
      deadline=$((SECONDS + ${toString deadlineSec}))
      grace_deadline=$((SECONDS + 20))

      wait_until() {
        while ((SECONDS < $1)); do
          kill -0 "$pid" 2>/dev/null || return 0
          ${lib.getExe' pkgs.coreutils "sleep"} 1
        done
        return 1
      }

      echo "Requesting ${service} in Crosvm guest ${name}"
      ${lib.getExe' pkgs.coreutils "timeout"} 10s \
        ${lib.getExe' pkgs.givc-cli "givc-cli"} ${cliArgs} \
        start service --vm ${lib.escapeShellArg name} ${lib.escapeShellArg service} \
        || echo "WARN: GIVC shutdown request for ${name} failed" >&2

      wait_until "$grace_deadline" && exit 0
      echo "WARN: forcing Crosvm ${name} to stop" >&2
      ${crosvm} --no-syslog stop ${lib.escapeShellArg socket} \
        || echo "WARN: Crosvm stop request for ${name} failed" >&2
      wait_until "$deadline" && exit 0
      echo "ERROR: Crosvm ${name} did not stop within ${toString deadlineSec}s" >&2
      exit 1
    '';
  mkVerifyScript =
    name:
    pkgs.writeShellScript "verify-crosvm-${name}-stopped" ''
      pid="''${MAINPID:-}"
      [ -z "$pid" ] || ! kill -0 "$pid" 2>/dev/null || {
        echo "ERROR: graceful shutdown left Crosvm ${name} running" >&2
        exit 1
      }
    '';
in
{
  _file = ./crosvm-shutdown.nix;

  config = lib.mkIf (config.nixpkgs.hostPlatform.isAarch64 && crosvmVms != { }) {
    systemd.services = lib.mkMerge (
      lib.mapAttrsToList (name: vm: {
        "microvm@${name}".serviceConfig = {
          TimeoutStopSec = "35";
          ExecStop = lib.mkForce [
            ""
            "+${mkVerifyScript name}"
          ];
        };
        "ghaf-crosvm-shutdown-${name}" = {
          description = "Gracefully shut down Crosvm guest ${name}";
          wantedBy = [ "microvm@${name}.service" ];
          partOf = [ "microvm@${name}.service" ];
          after = [ "microvm@${name}.service" ];
          serviceConfig = {
            Type = "oneshot";
            RemainAfterExit = true;
            ExecStart = lib.getExe' pkgs.coreutils "true";
            ExecStop = mkStopScript name vm (guestService name vm);
            TimeoutStopSec = "35";
            CapabilityBoundingSet = [ "CAP_KILL" ];
            NoNewPrivileges = true;
            PrivateTmp = true;
            ProtectHome = true;
            ProtectSystem = "strict";
          };
        };
      }) crosvmVms
    );
  };
}
