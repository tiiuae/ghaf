# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  pkgs,
  name,
  cgroupRoot ? "/sys/fs/cgroup",
  selfCgroup ? "/proc/self/cgroup",
}:
pkgs.writeShellScript "guard-crosvm-${name}-start" ''
  set -euo pipefail
  cgroup=
  while IFS=: read -r hierarchy _controllers path; do
    if [[ "$hierarchy" == 0 ]]; then cgroup="$path"; break; fi
  done < ${selfCgroup}
  # ExecStartPre may run in .control; inspect the entire service, including
  # a VMM retained by KillMode=none after systemd has forgotten its MainPID.
  while [[ "$cgroup" == /* && "$cgroup" != *.service ]]; do
    cgroup="''${cgroup%/*}"
  done
  if [[ "$cgroup" != /*.service || ! -r "${cgroupRoot}$cgroup/cgroup.procs" ]]; then
    echo "ERROR: cannot inspect Crosvm ${name} service cgroup; refusing to start" >&2
    exit 1
  fi
  shopt -s globstar nullglob
  for procs in "${cgroupRoot}$cgroup"/cgroup.procs "${cgroupRoot}$cgroup"/**/cgroup.procs; do
    # Empty child cgroups can disappear during traversal.
    [[ -e "$procs" ]] || continue
    while read -r pid; do
      if [[ "$pid" != "$$" ]]; then
        echo "ERROR: Crosvm ${name} retains process $pid after incomplete shutdown; refusing to start another VMM" >&2
        exit 1
      fi
    done < "$procs"
  done
''
