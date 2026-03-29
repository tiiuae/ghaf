# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# ClamAV script helpers
#
# Usage: scripts = import ./scripts.nix { inherit config lib pkgs; };
#
{
  config,
  lib,
  pkgs,
}:
let
  cfg = config.ghaf.security.clamav;
in
{
  # Wait for internet connectivity by checking NTP server reachability
  waitForInternet = pkgs.writeShellApplication {
    name = "wait-for-internet";
    runtimeInputs = [ pkgs.netcat ];
    text = ''
      servers=(${
        lib.concatMapStringsSep " " lib.escapeShellArg config.networking.timeServers
      } "time.cloudflare.com")
      while true; do
        for server in "''${servers[@]}"; do
          if nc -z -u -w 1 "$server" 123 2>/dev/null; then
            exit 0
          fi
        done
        sleep 30
      done
    '';
  };

  clamavScanner = pkgs.writeShellApplication {
    name = "clamav-scanner";
    runtimeInputs = [
      config.services.clamav.package
      pkgs.ghaf-virtiofs-tools
      pkgs.socat
    ];
    text = ''
      case "$1" in
        # on-access is configured via daemon config
        on-modify)
          DIRS=(${lib.concatStringsSep " " (map lib.escapeShellArg cfg.scan.on-modify.directories)})
          EXCLUDES=(${lib.concatStringsSep " " (map lib.escapeShellArg cfg.scan.on-modify.excludeDirectories)})
          ;;
        on-schedule)
          DIRS=(${lib.concatStringsSep " " (map lib.escapeShellArg cfg.scan.on-schedule.directories)})
          EXCLUDE_DIRS=${lib.escapeShellArg (lib.concatStringsSep "|" cfg.scan.on-schedule.excludeDirectories)}
          ;;
        *)          echo "Usage: $0 <on-access|on-modify|on-schedule>" >&2; exit 1 ;;
      esac

      case "$1" in
        on-access)
          echo "Initial scan: ''${DIRS[*]}"
          clamdscan --fdpass --multiscan --infected --allmatch --move="${cfg.quarantineDirectory}" "''${DIRS[@]}" || true

          echo "Starting on-access monitoring..."
          clamonacc --wait --fdpass --allmatch --foreground --move="${cfg.quarantineDirectory}"
          ;;
        on-modify)
          [[ ''${#DIRS[@]} -eq 0 ]] && { echo "No directories to monitor for $1"; exit 0; }
          echo "Starting on-modify monitoring for: ''${DIRS[*]}"

          clamd-vclient \
            ${
              if cfg.daemon.enable then
                "--socket"
              else
                "--cid ${toString cfg.scan.on-modify.clientConfig.cid} --port ${toString cfg.scan.on-modify.clientConfig.port}"
            } \
            --action quarantine \
            --quarantine-dir "${cfg.quarantineDirectory}" \
            ''${EXCLUDES[@]:+--exclude "''${EXCLUDES[@]}"} \
            --watch "''${DIRS[@]}"
          ;;
        on-schedule)
          [[ ''${#DIRS[@]} -eq 0 ]] && { echo "No directories to monitor for $1"; exit 0; }
          echo "Scheduled scan: ''${DIRS[*]}"

          set +e
          scan_output=$(clamscan \
            ''${EXCLUDE_DIRS:+--exclude-dir="$EXCLUDE_DIRS"} \
            --multiscan --infected --allmatch --no-summary \
            --move="${cfg.quarantineDirectory}" "''${DIRS[@]}" 2>&1)
          scan_exit_code=$?
          set -e

          echo "$scan_output"
          case $scan_exit_code in
            0) echo "Scan completed - no threats found" ;;
            1)
              # Parse and notify for each infected file
              while IFS= read -r line; do
                [[ "$line" =~ ^(.+):[[:space:]]+(.+)[[:space:]]+FOUND$ ]] || continue
                alert="Malware ''${BASH_REMATCH[2]} was detected in file: ''${BASH_REMATCH[1]}"
                echo "$alert" | socat - UNIX-CONNECT:/run/clamav/notify.sock 2>/dev/null || echo "$alert" >&2
              done <<< "$scan_output"
              ;;
            *) echo "Scan error occurred" >&2; exit 2 ;;
          esac
      esac
    '';
  };

  clamavEventHandler = pkgs.writeShellApplication {
    name = "clamav-event-handler";
    runtimeInputs = [ pkgs.socat ];
    text = ''
      # Custom ClamAV virus event handler script
      [[ $# -ne 2 ]] && { echo "Usage: $0 <filename> <virusname>" >&2; exit 1; }
      [[ -z "$1" || -z "$2" ]] && { echo "Both filepath and virusname must be provided." >&2; exit 1; }
      CLAM_VIRUSEVENT_FILENAME="$1"
      CLAM_VIRUSEVENT_VIRUSNAME="$2"
      alert="Malware $CLAM_VIRUSEVENT_VIRUSNAME was detected in file: $CLAM_VIRUSEVENT_FILENAME"
      echo "$alert" >&2

      # Send notification via socket
      if [[ -S /run/clamav/notify.sock ]]; then
        echo "$alert" | socat - UNIX-CONNECT:/run/clamav/notify.sock || {
          echo "Failed to send notification via socket" >&2
        }
      else
        echo "Notification socket not available" >&2
      fi
    '';
  };

  # User notification script; this runs as a separate service that
  # has no restrictions on network communication
  givcNotify = pkgs.writeShellApplication {
    name = "givc-notify";
    runtimeInputs = [
      pkgs.givc-cli
      pkgs.socat
    ];
    text = ''
      # Read message (5s timeout, 4KB max)
      MESSAGE=$(socat -T5 -u STDIN STDOUT,readbytes=4096 2>/dev/null) || MESSAGE=""
      if [[ -z "$MESSAGE" ]]; then
        echo "Invalid or oversized message received" >&2
        exit 1
      fi

      # Send notification via givc-cli with retries
      MESSAGE_SENT=false
      SECONDS=0
      while [[ "$MESSAGE_SENT" != "true" && $SECONDS -lt 10 ]]; do
        if givc-cli ${lib.replaceString "/run" "/etc" config.ghaf.givc.cliArgs} notify-user gui-vm \
        --event "ClamAV Alert" \
        --title "Malware Found" \
        --urgency "critical" \
        --message "$MESSAGE"; then
          MESSAGE_SENT=true
        else
          echo "Retrying notification via givc-cli..." >&2
          sleep 1
        fi
      done

      if [[ "$MESSAGE_SENT" == "true" ]]; then
        echo "Notification sent via givc-cli"
      else
        echo "Failed to send notification via givc-cli: $MESSAGE" >&2
        exit 1
      fi
    '';
  };
}
