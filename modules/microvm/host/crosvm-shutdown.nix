# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  config,
  lib,
  pkgs,
  ...
}:
let
  deadlineSec = 90;
  graceSec = 60;
  retrySec = 5;
  cliArgs = lib.replaceStrings [ "/run" ] [ "/etc" ] config.ghaf.givc.cliArgs;
  crosvmVms = lib.filterAttrs (
    _: vm:
    let
      vmConfig = lib.ghaf.vm.getConfig vm;
    in
    vmConfig != null && vmConfig.microvm.hypervisor == "crosvm"
  ) config.microvm.vms;
  shutdownLastVms = lib.attrNames (
    lib.filterAttrs (_: vm: (lib.ghaf.vm.getConfig vm).ghaf.shutdownLast) crosvmVms
  );
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
  requiresQuiesce = vm: guestService "" vm == "ghaf-mgbe0-poweroff.service";
  mkStopScript =
    name: vm:
    import ./crosvm-shutdown-script.nix {
      inherit
        lib
        pkgs
        name
        cliArgs
        deadlineSec
        graceSec
        retrySec
        ;
      stateDir = config.microvm.stateDir;
      service = guestService name vm;
      allowForcedStop = !requiresQuiesce vm;
    };
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

  config =
    lib.mkIf (config.nixpkgs.hostPlatform.isAarch64 && config.ghaf.givc.enable && crosvmVms != { })
      {
        systemd.services = lib.mkMerge (
          lib.mapAttrsToList (name: vm: {
            "microvm@${name}" = {
              unitConfig.SurviveFinalKillSignal = lib.mkIf (requiresQuiesce vm) true;
              serviceConfig = {
                TimeoutStopSec = lib.mkForce "95";
                # A timed-out quiesce must not turn into systemd killing an active DMA owner.
                KillMode = lib.mkIf (requiresQuiesce vm) (lib.mkForce "none");
                ExecStartPre = lib.mkIf (requiresQuiesce vm) (
                  lib.mkBefore [
                    (import ./crosvm-start-guard.nix { inherit pkgs name; })
                  ]
                );
                ExecStop = lib.mkForce [
                  ""
                  (mkVerifyScript name)
                ];
              };
            };
            "ghaf-crosvm-shutdown-${name}" = {
              description = "Gracefully shut down Crosvm guest ${name}";
              wantedBy = [ "microvm@${name}.service" ];
              partOf = [ "microvm@${name}.service" ];
              # Keep the GIVC coordinator alive until the other shutdown helpers finish.
              after = [
                "microvm@${name}.service"
              ]
              ++ lib.optionals (!(lib.elem name shutdownLastVms)) (
                map (last: "ghaf-crosvm-shutdown-${last}.service") shutdownLastVms
              );
              serviceConfig = {
                Type = "oneshot";
                RemainAfterExit = true;
                ExecStart = lib.getExe' pkgs.coreutils "true";
                ExecStop = mkStopScript name vm;
                WorkingDirectory = "${config.microvm.stateDir}/${name}";
                TimeoutStopSec = "95";
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
