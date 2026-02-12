# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# A debug script that allows executing applications from the command line.
{
  writeShellApplication,
  gawk,
}:
writeShellApplication {
  name = "ghaf-open";
  runtimeInputs = [ gawk ];
  text = ''
    APPS=/run/current-system/sw/share/applications
    RED="\e[31m"
    ENDCOLOR="\e[0m"

    help_msg() {
        cat <<EOF
    Usage: $(basename "$0") [OPTIONS] [APPLICATION] [ARGS...]

    Options:
        -l, --list            List available applications by their Name field and exit.
        -h, --help            Show this help message and exit.

    Examples:
        $(basename "$0") slack
        $(basename "$0") --list
    EOF
    }

    extract_exec() {
        awk -F= '
        /^Exec=/ {
            cmd=$2
            gsub(/ %[fFuUdDnNickvm]/, "", cmd)
            print cmd
            exit
        }
        ' "$1"
    }

    list_apps() {
        for de in "$APPS"/*.desktop; do
            # Skip entries without Exec field
            grep -qE '^Exec=.+$' "$de" || continue
            # Skip entries with NoDisplay=true
            grep -q 'NoDisplay=true' "$de" && continue
            # Prefer Name, fall back to filename
            name=$(awk -F= '
                /^Name=/ {
                    print $2
                    found=1
                    exit
                }
                END {
                    if (!found) {
                        gsub(/^.*\//, "", FILENAME)
                        gsub(/\.desktop$/, "", FILENAME)
                        print FILENAME
                    }
                }
            ' "$de")
            echo "$name"
        done
    }

    run_app() {
        APP=
        echo "Trying to find application by Name..."

        shopt -s dotglob
        for de in "$APPS"/*.desktop; do
            awk -F= -v name="$1" '
                BEGIN { in_section=0; n=0; e=0; nd=0 }

                /^\[Desktop Entry\]/ { in_section=1; next }
                /^\[/ { in_section=0 }

                in_section && /^Name=/      { n = ($2 == name) }
                in_section && /^Exec=/      { e = 1 }
                in_section && /^NoDisplay=/ { nd = ($2 == "true") }

                END { exit !(n && e && !nd) }
            ' "$de" && {
                APP="$de"
                break
            }
        done
        shopt -u dotglob

        if [[ -z "$APP" ]]; then
            echo "Trying to find application by filename..."
            if [[ -f "$APPS/$1.desktop" ]]; then
                APP="$APPS/$1.desktop"
            fi
        fi
        if [[ -z "$APP" ]]; then
            echo -e "''${RED}No application found with 'Name=$1' or filename '$1.desktop' ''${ENDCOLOR}" >&2
            return 1
        fi
        echo "Found $APP"
        exec_cmd=$(extract_exec "$APP")
        if [[ -n "$exec_cmd" ]]; then
            echo "Starting application from $APP with command: $exec_cmd"
            eval "$exec_cmd ''${*:2}"
            return 0
        else
            echo "Desktop entry $APP has no 'Exec' field" >&2
            return 1
        fi
    }

    if [[ $# -lt 1 ]]; then
        help_msg
        exit 0
    fi

    case "$1" in
    -l | --list)
        list_apps
        ;;
    -h | --help)
        help_msg
        ;;
    *)
        run_app "$1" "''${*:2}"
        ;;
    esac
  '';
  meta = {
    description = "Open applications from the command line";
    platforms = [
      "aarch64-linux"
      "x86_64-linux"
    ];
  };
}
