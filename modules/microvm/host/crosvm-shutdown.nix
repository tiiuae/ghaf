# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  config,
  lib,
  pkgs,
  ...
}:
let
  deadlineSec = 120;
  cliArgs = lib.replaceStrings [ "/run" ] [ "/etc" ] config.ghaf.givc.cliArgs;
  crosvmVms = lib.filterAttrs (
    _: vm: (lib.ghaf.vm.getConfig vm).microvm.hypervisor == "crosvm"
  ) config.microvm.vms;
  guestService =
    _name: vm:
    let
      vmConfig = lib.ghaf.vm.getConfig vm;
      services =
        (vmConfig.givc.sysvm.capabilities.services or [ ]) ++ (vmConfig.ghaf.givc.appvm.services or [ ]);
    in
    lib.findFirst (service: lib.elem service services) "poweroff.target" [
      "ghaf-mgbe0-poweroff.service"
      "ghaf-crosvm-poweroff.service"
      "poweroff.target"
    ];
  mkStopScript =
    name: service:
    pkgs.writeShellScript "stop-crosvm-${name}" ''
      set -u
      unit=${lib.escapeShellArg "microvm@${name}.service"}
      pid=$(${lib.getExe' pkgs.systemd "systemctl"} show -p MainPID --value "$unit")
      [ -n "$pid" ] && [ "$pid" != 0 ] || exit 0
      deadline=$((SECONDS + ${toString deadlineSec}))

      echo "Requesting ${service} in Crosvm guest ${name}"
      ${lib.getExe' pkgs.coreutils "timeout"} 10s \
        ${lib.getExe' pkgs.givc-cli "givc-cli"} ${cliArgs} \
        start service --vm ${lib.escapeShellArg name} ${lib.escapeShellArg service} \
        || echo "WARN: GIVC shutdown request for ${name} failed" >&2

      while ((SECONDS < deadline)); do
        kill -0 "$pid" 2>/dev/null || exit 0
        ${lib.getExe' pkgs.coreutils "sleep"} 1
      done
      echo "ERROR: guest-owned shutdown left Crosvm ${name} running after ${toString deadlineSec}s" >&2
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
          TimeoutStopSec = "125";
          ExecStop = lib.mkForce [
            ""
            (mkVerifyScript name)
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
            ExecStop = mkStopScript name (guestService name vm);
            TimeoutStopSec = "125";
            CapabilityBoundingSet = [
              "CAP_DAC_OVERRIDE"
              "CAP_KILL"
            ];
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
