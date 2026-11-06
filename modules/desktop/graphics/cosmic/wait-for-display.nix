# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{ writeShellApplication, coreutils }:
writeShellApplication {
  name = "wait-for-display";
  runtimeInputs = [ coreutils ];
  text = ''
    drm_root=$1
    shift

    while true; do
      for connector in "$drm_root"/card*-*; do
        if {
          read -r status < "$connector/status" &&
          [[ "$status" == connected ]] &&
          read -r mode < "$connector/modes" &&
          [[ -n "$mode" ]]
        } 2>/dev/null; then
          exec "$@"
        fi
      done
      sleep 1
    done
  '';
}
