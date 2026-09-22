# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  config,
  lib,
  pkgs,
  ...
}:
let
  inherit (lib)
    mkEnableOption
    mkIf
    mkOption
    types
    ;
  recCfg = config.ghaf.logging.recovery;
  ghafClockJumpWatcher = pkgs.writeShellApplication {
    name = "ghaf-clock-jump-watcher";
    runtimeInputs = with pkgs; [
      coreutils
      gawk
      gnugrep
      systemd
    ];
    text = ''
      threshold="${toString recCfg.thresholdSeconds}"
      interval="${toString recCfg.intervalSeconds}"
      last_real="$(date +%s)"
      last_up="$(cut -d' ' -f1 /proc/uptime)"

      # Cursors retain file order across clock jumps and avoid rescanning the boot.
      cursor=""

      read_journald_since_cursor() {
        if [ -n "$cursor" ]; then
          journalctl -u systemd-journald.service --after-cursor="$cursor" \
            --show-cursor --output=short-unix --quiet --no-pager 2>/dev/null || true
        else
          journalctl -b -u systemd-journald.service \
            --show-cursor --output=short-unix --quiet --no-pager 2>/dev/null || true
        fi
      }

      cursor_from_output() {
        printf '%s\n' "$1" | { grep '^-- cursor: ' || true; } | tail -1 \
          | sed 's/^-- cursor: //'
      }

      # Monotonic-clock notices must not trigger realtime recovery.
      jump_epochs_from_output() {
        printf '%s\n' "$1" | { grep -v '^-- cursor: ' || true; } \
          | { grep -F \
              -e "Time jumped backwards, rotating" \
              -e "Realtime clock jumped backwards relative to last journal entry, rotating" || true; } \
          | awk '$1 ~ /^[0-9]+([.][0-9]+)?$/ { split($1, ts, "."); print ts[1] }'
      }

      # Ignore clock jumps that predate this watcher invocation.
      raw="$(read_journald_since_cursor)"
      seen_cursor="$(cursor_from_output "$raw")"
      [ -z "$seen_cursor" ] || cursor="$seen_cursor"

      while true; do
        sleep "$interval"
        real="$(date +%s)"
        up="$(cut -d' ' -f1 /proc/uptime)"

        drift="$(awk -v r1="$last_real" -v r2="$real" -v u1="$last_up" -v u2="$up" \
          'BEGIN{print (r2-r1) - (u2-u1)}')"

        abs="$(awk -v d="$drift" 'BEGIN{print (d<0)?-d:d}')"

        raw="$(read_journald_since_cursor)"
        seen_cursor="$(cursor_from_output "$raw")"
        [ -z "$seen_cursor" ] || cursor="$seen_cursor"
        new_epochs="$(jump_epochs_from_output "$raw")"

        if awk -v a="$abs" -v t="$threshold" 'BEGIN{exit !(a>=t)}' \
          || [ -n "$new_epochs" ]; then
          systemctl start ghaf-journal-alloy-recover.service || true
        fi

        last_real="$real"
        last_up="$up"
      done
    '';
  };

  ghafJournalAlloyRecover = pkgs.writeShellApplication {
    name = "ghaf-journal-alloy-recover";
    runtimeInputs = with pkgs; [
      coreutils
      gawk
      gnugrep
      systemd
    ];
    text = ''
      stamp="/run/ghaf-journal-alloy-recover.stamp"
      now_ms="$(awk '{printf "%d\n", $1 * 1000}' /proc/uptime)"
      cooldown="${toString recCfg.cooldownSeconds}"
      cooldown_ms=$((cooldown * 1000))
      restart_if_installed() {
        local unit="$1"

        if systemctl cat "$unit" >/dev/null 2>&1; then
          systemctl restart "$unit"
        else
          echo "$unit not installed, skipping restart"
        fi
      }

      if [ -e "$stamp" ]; then
        last="$(cat "$stamp" 2>/dev/null || echo 0)"
        case "$last" in
          ""|*[!0-9]*)
            last=0
            ;;
        esac

        if [ "$last" -le "$now_ms" ] && [ "$((now_ms-last))" -lt "$cooldown_ms" ]; then
          exit 0
        fi
      fi
      echo "$now_ms" > "$stamp"

      restart_if_installed systemd-journal-upload.service
      restart_if_installed alloy.service
    '';
  };
in
{
  _file = ./common.nix;

  # Creating logging configuration options needed across the host and vms
  options.ghaf.logging = {
    enable = mkEnableOption "logging service (journal clients upload logs to admin-vm, admin-vm forwards to Loki)";

    listener.address = mkOption {
      description = ''
        Listener address where journal clients upload logs to admin-vm.
      '';
      type = types.str;
      default = "";
    };

    listener.port = mkOption {
      description = ''
        Listener port for systemd-journal-remote on admin-vm.
        This port is also opened in the admin-vm firewall.
      '';
      type = types.port;
      default = 9999;
    };

    listener.serverName = mkOption {
      description = ''
        Optional TLS server name used by log producers when
        verifying the admin-vm listener certificate.
      '';
      type = types.nullOr types.str;
      default = null;
    };

    journalRetention = {
      enable = mkOption {
        description = ''
          Enable local journal retention configuration.
          This configures systemd-journald to retain logs locally for a specified period.
        '';
        type = types.bool;
        default = true;
      };

      maxRetention = mkOption {
        description = ''
          Period of time to retain journal logs locally.
          After this period, old logs will be deleted automatically.
          This setting takes time values which may be suffixed with the units:
          'year', 'month', 'week', 'day', 'h' or ' m' to override the default time unit of seconds.
        '';
        type = types.str;
        default = "30day";
      };

      maxDiskUsage = mkOption {
        description = ''
          Maximum disk space that journal logs can occupy.
          Accepts sizes like "500M", "1G", etc.
        '';
        type = types.str;
        default = "500M";
      };

      MaxFileSec = mkOption {
        description = ''
          The maximum time to store entries in a single journal file before rotating to the next one.
          This setting takes time values which may be suffixed with the units:
          'year', 'month', 'week', 'day', 'h' or ' m' to override the default time unit of seconds.
        '';
        type = types.str;
        default = "1day";
      };

      syncInterval = mkOption {
        description = ''
          journald SyncIntervalSec: how often journal data is fsync'd to disk.
          Lower values shrink the window of unsynced data lost on an unclean kill
          (host crash, power loss, stop timeout), at the cost of more frequent
          fsyncs. systemd's default is 5m.
        '';
        type = types.str;
        default = "30s";
      };
    };

    recovery = {
      enable = (mkEnableOption "log-forwarder recovery after realtime clock jumps") // {
        default = true;
      };

      thresholdSeconds = mkOption {
        description = "Only act on clock jumps >= this many seconds.";
        type = types.int;
        default = 30;
      };

      intervalSeconds = mkOption {
        description = "Polling interval used by the clock-jump watcher.";
        type = types.int;
        default = 5;
      };

      cooldownSeconds = mkOption {
        description = "Minimum time between recover executions.";
        type = types.int;
        default = 60;
      };

    };
  };

  config = lib.mkMerge [
    {
      # A late drop-in also overrides activation files left in /run after a switch.
      environment.etc."systemd/journald.conf.d/99-ghaf-sealing.conf".text = ''
        [Journal]
        Seal=no
      '';
    }
    (mkIf (config.ghaf.logging.enable && recCfg.enable) {
      systemd = {
        services.ghaf-clock-jump-watcher = {
          description = "Detect realtime clock jumps and trigger log-forwarder recovery";
          wantedBy = [ "multi-user.target" ];

          serviceConfig = {
            Type = "simple";
            Restart = "always";
            RestartSec = 2;
            ExecStart = lib.getExe ghafClockJumpWatcher;
          };
        };

        services.ghaf-journal-alloy-recover = {
          description = "Recover log forwarders after time jump";

          unitConfig = {
            StartLimitIntervalSec = "0";
          };

          serviceConfig = {
            Type = "oneshot";
            ExecStart = lib.getExe ghafJournalAlloyRecover;
          };
        };

        tmpfiles.rules = [
          # Create persistent journal dir with the standard perms/group.
          "d /var/log/journal 2755 root systemd-journal - -"
          "z /var/log/journal/%m 2755 root systemd-journal - -"
        ];
      };
    })
  ];
}
