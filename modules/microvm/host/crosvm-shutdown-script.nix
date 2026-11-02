# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  lib,
  pkgs,
  stateDir,
  cliArgs,
  name,
  service,
  allowForcedStop,
  deadlineSec ? 90,
  graceSec ? 60,
  retrySec ? 5,
}:
pkgs.writeShellScript "stop-crosvm-${name}" ''
  set -u
  unit=${lib.escapeShellArg "microvm@${name}.service"}
  pid=$(${lib.getExe' pkgs.systemd "systemctl"} show -p MainPID --value "$unit") || exit 1
  [ -n "$pid" ] && [ "$pid" != 0 ] || exit 0
  deadline=$((SECONDS + ${toString deadlineSec}))
  grace_deadline=$((SECONDS + ${toString graceSec}))

  wait_until() {
    while ((SECONDS < $1)); do
      kill -0 "$pid" 2>/dev/null || return 0
      ${lib.getExe' pkgs.coreutils "sleep"} 1
    done
    return 1
  }

  while ((SECONDS < grace_deadline)); do
    echo "Requesting ${service} in Crosvm guest ${name}"
    if ${lib.getExe' pkgs.coreutils "timeout"} 10s \
      ${lib.getExe' pkgs.givc-cli "givc-cli"} ${cliArgs} \
      start service --vm ${lib.escapeShellArg name} ${lib.escapeShellArg service}; then
      wait_until "$grace_deadline" && exit 0
      break
    fi
    echo "WARN: GIVC shutdown request for ${name} failed; retrying" >&2
    wait_until "$((SECONDS + ${toString retrySec}))" && exit 0
  done

  ${
    if allowForcedStop then
      ''
        echo "WARN: forcing a Crosvm stop for ${name}; guest logs and filesystems may not be flushed" >&2
        ${lib.escapeShellArg "${stateDir}/${name}/booted/bin/microvm-shutdown"} \
          || echo "WARN: MicroVM shutdown request for ${name} failed" >&2
        wait_until "$deadline" && exit 0
        echo "ERROR: Crosvm ${name} did not stop within ${toString deadlineSec}s" >&2
      ''
    else
      ''
        echo "ERROR: ${name} did not quiesce; refusing to force-stop a DMA-active guest" >&2
      ''
  }
  exit 1
''
