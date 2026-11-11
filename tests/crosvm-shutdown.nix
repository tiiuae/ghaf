# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  self,
  pkgs,
  lib,
  runCommand,
  writeShellScriptBin,
}:
let
  net =
    self.nixosConfigurations.nvidia-jetson-orin-agx-debug.config.microvm.vms.net-vm.evaluatedConfig;
  quiesce = writeShellScriptBin "quiesce-mgbe0" ''
    echo quiesce >> "$EVENTS"
    test "$MODE" = success
  '';
  poweroff = writeShellScriptBin "systemctl" ''
    echo "poweroff $*" >> "$EVENTS"
  '';
  guestPoweroff = pkgs.writeShellScript "test-mgbe0-poweroff" (
    lib.replaceStrings
      [
        (lib.getExe net.pkgs.nvidia-jetpack.orinVirtualizationSupport.quiesceMgbe0)
        "${net.pkgs.systemd}/bin/systemctl"
      ]
      [ (lib.getExe quiesce) (lib.getExe poweroff) ]
      (builtins.unsafeDiscardStringContext net.config.systemd.services.ghaf-mgbe0-poweroff.script)
  );
  systemd = writeShellScriptBin "systemctl" ''echo "$GUEST_PID"'';
  givc = writeShellScriptBin "givc-cli" ''
    echo request >> "$EVENTS"
    case "$MODE" in
      success) kill "$GUEST_PID" ;;
      reject) exit 1 ;;
      stalled) exit 0 ;;
    esac
  '';
  stop =
    allowForcedStop:
    import ../modules/microvm/host/crosvm-shutdown-script.nix {
      inherit lib allowForcedStop;
      pkgs = pkgs // {
        inherit systemd;
        givc-cli = givc;
      };
      name = "test-vm";
      service = "poweroff.target";
      stateDir = "state";
      cliArgs = "";
      graceSec = 1;
      retrySec = 0;
      deadlineSec = 3;
    };
  startGuard = import ../modules/microvm/host/crosvm-start-guard.nix {
    inherit pkgs;
    name = "test-vm";
    cgroupRoot = "cgroup";
    selfCgroup = "self-cgroup";
  };
  start = pkgs.writeShellScript "test-crosvm-start" ''
    echo "$$" > cgroup/system.slice/microvm@test-vm.service/.control/cgroup.procs
    exec ${startGuard}
  '';
in
runCommand "crosvm-shutdown" { } ''
  mkdir -p cgroup/system.slice/microvm@test-vm.service/{.control,vcpu}
  echo '0::/system.slice/microvm@test-vm.service/.control' > self-cgroup
  : > cgroup/system.slice/microvm@test-vm.service/cgroup.procs
  : > cgroup/system.slice/microvm@test-vm.service/vcpu/cgroup.procs
  ${start}
  for location in cgroup.procs vcpu/cgroup.procs; do
    echo 12345 > "cgroup/system.slice/microvm@test-vm.service/$location"
    if ${start} > log 2>&1; then exit 1; fi
    grep -q 'retains process 12345' log
    : > "cgroup/system.slice/microvm@test-vm.service/$location"
    ${start}
  done
  echo '0::/' > self-cgroup
  if ${start} > log 2>&1; then exit 1; fi
  grep -q 'cannot inspect' log
  mkdir -p state/test-vm/booted/bin
  cat > state/test-vm/booted/bin/microvm-shutdown <<'HELPER'
  #!${pkgs.runtimeShell}
  echo forced >> "$EVENTS"
  kill "$GUEST_PID"
  HELPER
  chmod +x state/test-vm/booted/bin/microvm-shutdown
  export EVENTS="$PWD/events"
  : > events
  export MODE=reject
  for attempt in 1 2; do
    if ${guestPoweroff}; then exit 1; fi
  done
  test "$(grep -c quiesce events)" = 2
  ! grep -q poweroff events
  export MODE=success
  ${guestPoweroff}
  grep -q 'poweroff start --no-block --job-mode=replace-irreversibly poweroff.target' events
  trap 'kill "$GUEST_PID" 2>/dev/null || true' EXIT
  for MODE in success reject stalled; do
    export MODE
    for forced in yes no; do
      : > events
      sleep 30 &
      export GUEST_PID=$!
      if [ "$forced" = yes ]; then script=${stop true}; else script=${stop false}; fi
      status=0
      "$script" > log 2>&1 || status=$?
      if [ "$MODE" = success ]; then
        test "$status" = 0
        ! kill -0 "$GUEST_PID" 2>/dev/null
        ! grep -q forced events
      elif [ "$forced" = yes ]; then
        test "$status" = 0
        grep -q forced events
        ! kill -0 "$GUEST_PID" 2>/dev/null
      else
        test "$status" = 1
        kill -0 "$GUEST_PID"
        ! grep -q forced events
        grep -q 'refusing to force-stop' log
        kill "$GUEST_PID"
      fi
      wait "$GUEST_PID" || true
    done
  done
  touch "$out"
''
