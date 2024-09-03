# Copyright 2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# A debug script that allows executing applications from the command line.
{ writeShellApplication, gawk, ... }:
writeShellApplication {
  name = "ghaf-open";
  runtimeInputs = [ gawk ];
  text = ''
    APPS=/run/current-system/sw/share/applications

    function list_apps() {
      for e in "$APPS"/*.desktop; do
        [[ -e "$e" ]] || continue  # in case of no entries

        basename "$e" .desktop
      done
    }

    if [ $# -eq 0 ]; then
      echo -e "Usage: ghaf-open <-l|application> [args...]\n"
      echo -e "\t-l\tList available applications"
      exit 1
    fi

    if [ "$1" = "-l" ]; then
      list_apps
      exit 0
    fi

    if [ ! -e "$APPS/$1.desktop" ]; then
      echo "No launcher entry for $1"
      exit 1
    fi

    eval "$(awk '/^Exec=/{sub(/^Exec=/, ""); print}' "$APPS/$1.desktop") ''${*:2}"
  '';
}
