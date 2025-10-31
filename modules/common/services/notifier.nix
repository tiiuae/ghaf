# Copyright 2025 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.ghaf.services.log-notifier;
  inherit (lib)
    concatStringsSep
    getExe
    literalExpression
    mapAttrsToList
    mkEnableOption
    mkIf
    mkOption
    types
    ;

  eventType = types.submodule {
    options = {
      unit = mkOption {
        type = types.str;
        description = "The systemd service unit to monitor (e.g., 'clamav-daemon.service').";
        example = "sshd.service";
      };
      filter = mkOption {
        type = types.str;
        description = "The string to filter for in the journal entries.";
        example = "Accepted publickey";
      };
      title = mkOption {
        type = types.str;
        default = "System Event";
        description = "The title of the desktop notification.";
      };
      criticality = mkOption {
        type = types.enum [
          "low"
          "normal"
          "critical"
        ];
        default = "normal";
        description = "The urgency level for the notification.";
      };
      icon = mkOption {
        type = types.str;
        default = "${pkgs.ghaf-artwork}/icons/security-red.svg";
        defaultText = "The default Ghaf security alert icon";
        description = "The icon to display in the notification.";
      };
      formatter = mkOption {
        type = types.str;
        default = "${pkgs.coreutils}/bin/cat";
        defaultText = "${pkgs.coreutils}/bin/cat (no formatting)";
        description = ''
          A command to extract information from the log to make it palatable for the user notification.
          Any executable needs to be specified with the nix store path (see example). Currently, the
          Cosmic UI does not support any fancy formatting or icons.

          Defaults to "cat" (no formatting).
        '';
        example = literalExpression ''
          ${pkgs.gawk}/bin/awk '
            /VIRUSALERT=/ {
              sub(/.*VIRUSALERT=/, "");
              printf "%s\n", $0;
            }
          '
        '';
      };
    };
  };

  # TODO this should be improved with an efficient application
  eventWatcher = pkgs.writeShellApplication {
    name = "event-watcher";
    runtimeInputs = [
      pkgs.systemd
      pkgs.jq
      pkgs.gnugrep
      pkgs.util-linux
      pkgs.socat
      pkgs.gawk
    ];
    text = ''
      # Broadcast a JSON payload to all active graphical user sessions
      broadcast_json() {
        local payload="$1"
        local uids

        uids=$(loginctl list-sessions --json=short | jq -r '.[] | select(.seat != null) | .uid')
        [[ -z "$uids" ]] && return 0

        for uid in $uids; do
          local user_socket
          user_socket=$(echo "${cfg.socketPath}" | awk -v uid="$uid" '{gsub(/%U/, uid); print}')

          if [ -S "$user_socket" ]; then
            for _ in $(seq 1 5); do
              if socat - "UNIX-CONNECT:$user_socket" >/dev/null 2>&1 <<<"$payload"; then
                break
              fi
              sleep 0.1
            done
          else
            echo "No socket found for user $uid at $user_socket" >&2
          fi
        done
      }
      export -f broadcast_json

      # Start a watcher process for each configured event
      ${concatStringsSep "\n" (
        mapAttrsToList (name: event: ''
          ( journalctl -u "${event.unit}" -f -n 0 | \
            grep --line-buffered "${event.filter}" | \
            while IFS= read -r line; do
              if ! formatted_message=$(echo "$line" | ${event.formatter}); then
                echo "Formatter failed for line: $line" >&2
                continue
              fi
              if [ -n "$formatted_message" ]; then
                json=$(jq -n \
                  --arg event "${name}" \
                  --arg title "${event.title}" \
                  --arg criticality "${event.criticality}" \
                  --arg icon "${event.icon}" \
                  --arg message "$formatted_message" \
                  '{event: $event, title: $title, criticality: $criticality, icon: $icon, message: $message}')
                broadcast_json "$json"
              fi
            done
          ) &
        '') cfg.events
      )}

      wait
    '';
  };

  eventNotifier = pkgs.writeShellApplication {
    name = "event-notifier";
    runtimeInputs = [
      pkgs.libnotify
      pkgs.jq
      pkgs.gawk
      pkgs.coreutils
      pkgs.util-linux
    ];
    text = ''
      # Exit if user has no graphical session
      SESSION_INFO=$(loginctl list-sessions --json=short | jq --argjson CUID "$UID" '.[] | select(.seat != null and .uid == $CUID)')
      [[ -z "$SESSION_INFO" ]] && exit 0

      # Retrieve last object
      LAST_OBJECT=$(cat)
      [[ -z "$LAST_OBJECT" ]] && exit 0

      event=$(jq -r '.event // "event"' <<<"$LAST_OBJECT")
      title=$(jq -r '.title // "System Event"' <<<"$LAST_OBJECT")
      criticality=$(jq -r '.criticality // "normal"' <<<"$LAST_OBJECT")
      icon=$(jq -r '.icon // ""' <<<"$LAST_OBJECT")
      message=$(jq -r '.message // ""' <<<"$LAST_OBJECT")

      # Call notify-send with the parsed arguments
      notify-send -t 10000 \
        -a "$event" \
        -u "$criticality" \
        ''${icon:+-h "string:image-path:$icon"} \
        "$title" \
        "$message"
    '';
  };

in
{
  options.ghaf.services.log-notifier = {
    enable = mkEnableOption ''
      user log notifier service. This service will monitor the system logs (systemd journal)
      and notify the user of registered events via desktop notifications
    '';
    events = mkOption {
      type = types.attrsOf eventType;
      default = { };
      description = "List of events to watch and create notifications.";
      example = literalExpression ''
        {
          "clamav-alert" = {
            unit = "clamav-daemon.service";
            filter = "FOUND";
            title = "Malware Detected!";
            criticality = "critical";
          };
        }
      '';
    };
    socketPath = mkOption {
      type = types.str;
      default = "/run/log/journal-notifier/user-%U.sock";
      description = ''
        The path template to the per-user UNIX socket (read-only). It contains the systemd specifier `%U`,
        which will be replaced by the user's ID.
      '';
      readOnly = true;
    };
  };
  config = mkIf cfg.enable {

    assertions = [
      {
        assertion = config.ghaf.profiles.graphics.enable;
        message = "The log notifier requires a graphical environment to send desktop notifications.";
      }
    ];

    users.users.journal-notifier = {
      isSystemUser = true;
      group = "journal-notifier";
      extraGroups = [ "systemd-journal" ];
    };
    users.groups.journal-notifier = { };

    systemd.tmpfiles.rules = [
      "d ${dirOf cfg.socketPath} 0770 root journal-notifier -"
    ];

    systemd.services.journal-event-watcher = {
      description = "Journal event watcher for user notifications";
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        Type = "simple";
        User = "journal-notifier";
        Group = "journal-notifier";
        ExecStart = "${getExe eventWatcher}";
        Restart = "always";
        RestartSec = "5s";
      };
    };
    systemd.user = {
      sockets.event-notifier = {
        description = "Notification event socket";
        wantedBy = [ "sockets.target" ];
        after = [
          "graphical-session.target"
          "journal-event-watcher.service"
        ];
        unitConfig.ConditionGroup = "journal-notifier";
        socketConfig = {
          ListenStream = cfg.socketPath;
          Accept = true;
          SocketMode = "0660";
          SocketGroup = "journal-notifier";
        };
      };
      services."event-notifier@" = {
        description = "Desktop user notification dispatcher";
        serviceConfig = {
          Type = "simple";
          StandardInput = "socket";
          ExecStart = "${getExe eventNotifier}";
        };
      };
    };
  };
}
