# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  writeShellApplication,
  wtype,
  inotify-tools,
}:
writeShellApplication {
  name = "ghaf-workspace";

  runtimeInputs = [
    wtype
    inotify-tools
  ];

  text = ''
    WORKSPACE_DIR="$HOME/.config/labwc"
    WORKSPACE_FILE="$WORKSPACE_DIR/current-workspace"
    MAX_WORKSPACES_FILE="$WORKSPACE_DIR/max-workspaces"

    if [ $# -eq 0 ]; then
        usage
    fi

    # Ensure the workspace directory exists
    mkdir -p "$WORKSPACE_DIR"

    read_workspace() {
        if [ ! -f "$WORKSPACE_FILE" ]; then
            echo "Initializing workspace file..."
            echo "1" > "$WORKSPACE_FILE" # Initialize workspace file if it doesn't exist
        fi
        read -r current_workspace < "$WORKSPACE_FILE"
    }

    write_workspace() {
        truncate -s 0 "$WORKSPACE_FILE"
        echo "$current_workspace" >> "$WORKSPACE_FILE"
    }

    read_max_workspaces() {
        if [ ! -f "$MAX_WORKSPACES_FILE" ]; then
            echo "Initializing max workspaces file..."
            echo "2" > "$MAX_WORKSPACES_FILE"
        fi
        read -r max_workspaces < "$MAX_WORKSPACES_FILE"
    }

    update_workspace() {
        if [ "$1" = "$current_workspace" ]; then
            return
        fi

        if [[ $1 -ge 1 && $1 -le $max_workspaces ]]; then
            current_workspace=$1
            write_workspace
            echo "Workspace updated to $current_workspace"
        else
            echo "Error: Workspace id must be between 1 and $max_workspaces."
            exit 1
        fi
    }

    subscribe() {
        if [ ! -f "$WORKSPACE_FILE" ]; then
            echo "Error: Workspace file not found"
            exit 1
        fi
            inotifywait -e close_write -m "$WORKSPACE_FILE" | \
            while read -r; do
                tail -n 1 "$WORKSPACE_FILE"
            done
    }

    usage() {
        echo "Usage: $0 {max {number} | max | next | prev | cur | switch {number} | path | update {number} | subscribe}"
        echo
        echo "Commands:"
        echo "  max [number]       Set or display the maximum number of workspaces."
        echo "                     If [number] is provided, sets the maximum number of workspaces"
        echo "                     If no [number] is provided, shows the current maximum number of workspaces"
        echo
        echo "  next               Switch to the next workspace"
        echo
        echo "  prev               Switch to the previous workspace"
        echo
        echo "  cur                Display the current active workspace number"
        echo
        echo "  switch [number]    Switch to the specified workspace identified by [number]"
        echo
        echo "  path               Display the file path where workspace information is stored"
        echo
        echo "  update [number]    Update the workspace configuration with the specified [number]"
        echo "                     Should be used if workspace changes were done by something other than this script"
        echo
        echo "  subscribe          Listen to workspace changes and print current workspace whenever a change is detected"
        exit 1
    }

    read_workspace
    read_max_workspaces

    case "$1" in
        max)
            if [ "$#" -eq 1 ]; then
                echo "$max_workspaces"
                exit 0
            fi
            echo "$2" > "$MAX_WORKSPACES_FILE"
            echo "Maximum number of workspaces set to $2"
            ;;

        next)
            if [[ $current_workspace -lt $max_workspaces ]]; then
                ((current_workspace++))
            else
                current_workspace=1
            fi
            write_workspace
            wtype -M win -k "$current_workspace" -m win
            echo "Switched to workspace $current_workspace"
            ;;

        prev)
            if [[ $current_workspace -gt 1 ]]; then
                ((current_workspace--))
            else
                current_workspace=$max_workspaces
            fi
            write_workspace
            wtype -M win -k "$current_workspace" -m win
            echo "Switched to workspace $current_workspace"
            ;;

        switch)
            if [ "$#" -eq 1 ]; then
                echo "No workspace id provided"
                exit 1
            fi
            update_workspace "$2"
            wtype -M win -k "$2" -m win
            ;;

        update)
            if [ "$#" -eq 1 ]; then
                echo "No workspace id provided"
                exit 1
            fi
            update_workspace "$2"
            ;;

        path)
            echo "$WORKSPACE_FILE"
            ;;

        cur)
            echo "$current_workspace"
            ;;

        subscribe)
            subscribe
            ;;

        *)
            usage
            ;;
    esac
  '';
  meta = {
    description = "Script to manage workspaces using wtype";
    platforms = [
      "aarch64-linux"
      "x86_64-linux"
    ];
  };
}
