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
  loggingStackEnabled = config.ghaf.logging.enable || config.ghaf.logging.fss.enable;
  clockReadyEnabled = config.ghaf.logging.fss.enable && recCfg.enable && recCfg.clockReady.enable;
  fssActivationCfg = config.ghaf.logging.fss.activation;
  fssActivationEnabled = config.ghaf.logging.fss.enable && fssActivationCfg.enable;
  # Effective time-sync wait before FSS activation; only applies when the
  # activation boundary is enabled. Computed once and reused below.
  effectiveSyncWaitSeconds = if fssActivationEnabled then fssActivationCfg.syncWaitSeconds else 0;

  ghafClockReady = pkgs.writeShellApplication {
    name = "ghaf-clock-ready";
    runtimeInputs = with pkgs; [
      coreutils
      gawk
      systemd
    ];
    text = ''
      stable_seconds="${toString recCfg.clockReady.stableSeconds}"
      max_wait_seconds="${toString recCfg.clockReady.maxWaitSeconds}"
      min_epoch="${toString recCfg.clockReady.minEpochSeconds}"
      max_epoch="${toString recCfg.clockReady.maxEpochSeconds}"
      ready_file="/run/ghaf-clock-ready"
      state_file="/run/ghaf-clock-ready-state"
      state_dir="/var/lib/ghaf/clock-ready"
      anchor_file="$state_dir/last-good-realtime"

      uptime_seconds() {
        awk '{printf "%d\n", $1}' /proc/uptime
      }

      read_epoch_file() {
        local path="$1"
        local value=""

        [ -r "$path" ] || return 0
        value="$(tr -d '\n' < "$path" 2>/dev/null || true)"
        case "$value" in
        "" | *[!0-9]*) return 0 ;;
        *) printf '%s\n' "$value" ;;
        esac
      }

      write_state() {
        local now_real now_up

        now_real="$(date +%s)"
        now_up="$(uptime_seconds)"
        {
          printf 'ready_established=%s\n' "$ready_established"
          printf 'sync_result=%s\n' "$sync_result"
          printf 'sync_value=%s\n' "$sync_value"
          printf 'realtime=%s\n' "$now_real"
          printf 'uptime_seconds=%s\n' "$now_up"
          printf 'min_allowed=%s\n' "$min_allowed"
          printf 'max_allowed=%s\n' "$max_epoch"
          printf 'anchor_epoch=%s\n' "''${anchor_epoch:-}"
          printf 'anchor_status=%s\n' "''${anchor_status:-unknown}"
        } > "$state_file"
        chmod 0644 "$state_file"
      }

      mkdir -p "$state_dir"

      anchor_epoch="$(read_epoch_file "$anchor_file")"
      anchor_status="missing"
      min_allowed="$min_epoch"
      if [ -n "$anchor_epoch" ] && [ "$anchor_epoch" -gt "$max_epoch" ]; then
        echo "Clock readiness ignoring future-poisoned anchor $anchor_epoch above maximum $max_epoch"
        anchor_status="ignored-future"
        anchor_epoch=""
      elif [ -n "$anchor_epoch" ] && [ "$anchor_epoch" -gt "$min_allowed" ]; then
        min_allowed="$anchor_epoch"
        anchor_status="accepted"
      elif [ -n "$anchor_epoch" ]; then
        anchor_status="below-minimum"
      fi

      start_up="$(uptime_seconds)"
      last_real="$(date +%s)"
      stable_since="$start_up"
      ready_established=0
      sync_result="not-started"
      sync_value="unknown"

      while true; do
        sleep 1
        now_up="$(uptime_seconds)"
        now_real="$(date +%s)"

        if [ "$now_real" -gt "$max_epoch" ]; then
          stable_since=""
          echo "Clock readiness waiting: realtime $now_real is above maximum $max_epoch"
        elif [ "$now_real" -lt "$min_allowed" ]; then
          stable_since=""
          echo "Clock readiness waiting: realtime $now_real is below minimum $min_allowed"
        elif [ "$now_real" -lt "$last_real" ]; then
          stable_since=""
          echo "Clock readiness waiting: realtime moved backwards from $last_real to $now_real"
        else
          if [ -z "$stable_since" ]; then
            stable_since="$now_up"
          fi

          if [ "$((now_up - stable_since))" -ge "$stable_seconds" ]; then
            echo "Clock readiness established after $stable_seconds stable seconds"
            ready_established=1
            break
          fi
        fi

        last_real="$now_real"

        if [ "$((now_up - start_up))" -ge "$max_wait_seconds" ]; then
          echo "Clock readiness max wait reached; allowing boot to continue with realtime $now_real"
          break
        fi
      done

      # NTP synchronization is intentionally NOT awaited here. This barrier runs
      # early (before systemd-journal-flush, which requires it, and before
      # sysinit.target), so networking/timesyncd has not started yet and the NTP
      # check could only ever hit its full timeout, stalling the journal flush on
      # every boot. The sync wait is handled later by ghaf-clock-sync.service,
      # which runs after networking and before journal-fss-setup.
      sync_result="deferred"

      now_real="$(date +%s)"
      if [ "$now_real" -gt "$max_epoch" ]; then
        echo "Clock readiness did not update last-good realtime: $now_real is above maximum $max_epoch"
      elif [ "$now_real" -ge "$min_allowed" ]; then
        printf '%s\n' "$now_real" > "$anchor_file"
        chmod 0644 "$anchor_file"
      elif [ "$ready_established" -eq 0 ]; then
        echo "Clock readiness fallback did not update last-good realtime: $now_real is below $min_allowed"
      fi

      write_state
      touch "$ready_file"
      chmod 0644 "$ready_file"
    '';
  };

  # Time-synchronization wait, split out of ghaf-clock-ready so it runs AFTER
  # networking/timesyncd and does not block the early journal flush. It best-effort
  # waits for NTP synchronization up to the configured bound before FSS activation,
  # then releases boot regardless (clock readiness is a gate, not a time authority).
  ghafClockSync = pkgs.writeShellApplication {
    name = "ghaf-clock-sync";
    runtimeInputs = with pkgs; [
      coreutils
      gawk
      systemd
    ];
    text = ''
      sync_wait_seconds="${toString effectiveSyncWaitSeconds}"
      sync_state_file="/run/ghaf-clock-sync-state"
      synced_file="/run/ghaf-clock-synced"

      uptime_seconds() {
        awk '{printf "%d\n", $1}' /proc/uptime
      }

      sync_result="not-started"
      sync_value="unknown"

      write_sync_state() {
        {
          printf 'sync_result=%s\n' "$sync_result"
          printf 'sync_value=%s\n' "$sync_value"
          printf 'sync_wait_seconds=%s\n' "$sync_wait_seconds"
          printf 'realtime=%s\n' "$(date +%s)"
          printf 'uptime_seconds=%s\n' "$(uptime_seconds)"
        } > "$sync_state_file"
        chmod 0644 "$sync_state_file"
      }

      if [ "$sync_wait_seconds" -le 0 ]; then
        sync_result="disabled"
      elif command -v timedatectl >/dev/null 2>&1; then
        sync_start_up="$(uptime_seconds)"
        while true; do
          sync_value="$(timedatectl show -p NTPSynchronized --value 2>/dev/null || true)"
          if [ "$sync_value" = "yes" ]; then
            sync_result="synchronized"
            echo "Clock sync observed system time synchronization"
            break
          fi

          now_up="$(uptime_seconds)"
          if [ "$((now_up - sync_start_up))" -ge "$sync_wait_seconds" ]; then
            sync_result="timeout"
            echo "Clock sync wait reached; allowing boot to continue with NTPSynchronized=''${sync_value:-unknown}"
            break
          fi

          sleep 1
        done
      else
        sync_result="timedatectl-unavailable"
        echo "Clock sync could not check time synchronization: timedatectl unavailable"
      fi

      write_sync_state
      touch "$synced_file"
      chmod 0644 "$synced_file"
    '';
  };

  ghafClockJumpWatcher = pkgs.writeShellApplication {
    name = "ghaf-clock-jump-watcher";
    runtimeInputs = with pkgs; [
      coreutils
      gawk
      systemd
    ];
    text = ''
      threshold="${toString recCfg.thresholdSeconds}"
      interval="${toString recCfg.intervalSeconds}"

      last_real="$(date +%s)"
      last_up="$(cut -d' ' -f1 /proc/uptime)"

      while true; do
        sleep "$interval"
        real="$(date +%s)"
        up="$(cut -d' ' -f1 /proc/uptime)"

        drift="$(awk -v r1="$last_real" -v r2="$real" -v u1="$last_up" -v u2="$up" \
          'BEGIN{print (r2-r1) - (u2-u1)}')"

        abs="$(awk -v d="$drift" 'BEGIN{print (d<0)?-d:d}')"

        if awk -v a="$abs" -v t="$threshold" 'BEGIN{exit !(a>=t)}'; then
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
      machine_id="$(cat /etc/machine-id)"
      state_dir="/var/log/journal/$machine_id"
      recovery_receipts_file="$state_dir/fss-recovery-receipts"
      activation_state_file="$state_dir/fss-activation-state"
      activation_baseline_file="$state_dir/fss-baseline-boot"
      fss_activation_enabled="${if fssActivationEnabled then "1" else "0"}"
      max_recovery_receipts="${toString recCfg.maxReceipts}"
      stamp="/run/ghaf-journal-alloy-recover.stamp"
      now_ms="$(awk '{printf "%d\n", $1 * 1000}' /proc/uptime)"
      cooldown="${toString recCfg.cooldownSeconds}"
      cooldown_ms=$((cooldown * 1000))
      before_file="$(mktemp)"

      cleanup() {
        rm -f "$before_file"
      }

      list_archived_system_journals() {
        local journal_dir
        local archive_path

        for journal_dir in \
          "/var/log/journal/$machine_id" \
          "/run/log/journal/$machine_id"; do
          for archive_path in "$journal_dir"/system@*.journal; do
            [ -f "$archive_path" ] || continue
            printf '%s\n' "$archive_path"
          done
        done | sort -u
      }

      current_boot_id() {
        cat /proc/sys/kernel/random/boot_id 2>/dev/null || echo unknown-boot
      }

      fss_activation_complete_current_boot() {
        local state=""
        local state_boot=""
        local baseline_boot=""
        local boot

        [ "$fss_activation_enabled" = 1 ] || return 0
        [ -r "$activation_state_file" ] || return 1
        [ -r "$activation_baseline_file" ] || return 1

        state="$(awk -F '\t' 'NR == 1 { print $1 }' "$activation_state_file")"
        state_boot="$(awk -F '\t' 'NR == 1 { print $2 }' "$activation_state_file")"
        baseline_boot="$(tr -d '[:space:]' < "$activation_baseline_file")"
        boot="$(current_boot_id)"

        [ "$state" = "active" ] \
          && [ "$state_boot" = "$boot" ] \
          && [ "$baseline_boot" = "$boot" ]
      }

      valid_sha256() {
        printf '%s' "$1" | grep -Eq '^[0-9a-f]{64}$'
      }

      record_recovery_receipt() {
        local archive_path="$1"
        local inode size mtime sha boot event

        [ -n "$archive_path" ] || return 0
        [ -f "$archive_path" ] || return 0

        inode=$(stat -c %i "$archive_path" 2>/dev/null || true)
        size=$(stat -c %s "$archive_path" 2>/dev/null || true)
        mtime=$(stat -c %Y "$archive_path" 2>/dev/null || true)
        sha=$(sha256sum "$archive_path" 2>/dev/null | cut -d' ' -f1 || true)
        boot="$(current_boot_id)"
        event="''${INVOCATION_ID:-$boot}"

        if [ -z "$inode" ] || [ -z "$size" ] || [ -z "$mtime" ] || ! valid_sha256 "$sha"; then
          echo "Could not record FSS recovery receipt for $archive_path: missing stat or sha256 evidence"
          return 0
        fi

        if [ -f "$recovery_receipts_file" ] \
          && awk -F '\t' -v p="$archive_path" -v i="$inode" -v s="$size" \
            '$2 == p && $3 == i && $4 == s { found = 1 } END { exit found ? 0 : 1 }' \
            "$recovery_receipts_file"; then
          return 0
        fi

        printf 'v1\t%s\t%s\t%s\t%s\t%s\t%s\tclock-jump-recovery\t%s\n' \
          "$archive_path" "$inode" "$size" "$boot" "$mtime" "$sha" "$event" \
          >> "$recovery_receipts_file"
        chmod 0644 "$recovery_receipts_file"
        echo "Recorded FSS recovery archive receipt: $archive_path"
      }

      prune_recovery_receipts() {
        local total excess tmp

        [ -f "$recovery_receipts_file" ] || return 0
        total=$(wc -l < "$recovery_receipts_file" 2>/dev/null || echo 0)
        [ "$total" -gt "$max_recovery_receipts" ] || return 0

        excess=$((total - max_recovery_receipts))
        tmp=$(mktemp)
        tail -n "$max_recovery_receipts" "$recovery_receipts_file" > "$tmp"
        mv "$tmp" "$recovery_receipts_file"
        chmod 0644 "$recovery_receipts_file"
        echo "Recovery receipts exceeded $max_recovery_receipts; evicted $excess oldest record(s)"
      }

      record_recovery_archives() {
        local after_file
        local archive_path

        mkdir -p "$state_dir"
        touch "$recovery_receipts_file"
        chmod 0644 "$recovery_receipts_file"

        after_file="$(mktemp)"
        list_archived_system_journals > "$after_file"

        while IFS= read -r archive_path || [ -n "$archive_path" ]; do
          [ -n "$archive_path" ] || continue
          if ! grep -Fxq "$archive_path" "$before_file"; then
            record_recovery_receipt "$archive_path"
          fi
        done < "$after_file"

        rm -f "$after_file"
        prune_recovery_receipts
      }

      trap cleanup EXIT
      if ! fss_activation_complete_current_boot; then
        echo "FSS activation is not complete for the current boot; skipping journal recovery"
        exit 0
      fi
      list_archived_system_journals > "$before_file"

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

      systemd-tmpfiles --create --prefix /var/log/journal
      systemctl restart systemd-journald.service
      record_recovery_archives
      journalctl --rotate 2>/dev/null || true
      journalctl --sync 2>/dev/null || true
      record_recovery_archives

      restart_if_installed() {
        local unit="$1"

        if systemctl cat "$unit" >/dev/null 2>&1; then
          systemctl restart "$unit"
        else
          echo "$unit not installed, skipping restart"
        fi
      }

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
          fsyncs. Relevant to FSS: an unsynced tail can leave a torn, unverifiable
          sealed journal. systemd's default is 5m.
        '';
        type = types.str;
        default = "30s";
      };
    };

    recovery = {
      enable = (mkEnableOption "journald/log-forwarder recovery after realtime clock jumps") // {
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

      maxReceipts = mkOption {
        description = "Upper bound on retained content-bound recovery archive receipts.";
        type = types.int;
        default = 64;
      };

      clockReady = {
        enable = (mkEnableOption "clock readiness barrier for persistent sealed logging") // {
          default = true;
        };

        stableSeconds = mkOption {
          description = "Consecutive seconds of non-decreasing realtime required before persistent logging is released.";
          type = types.int;
          default = 20;
        };

        maxWaitSeconds = mkOption {
          description = "Maximum time to wait for clock readiness before allowing boot to continue.";
          type = types.int;
          default = 90;
        };

        minEpochSeconds = mkOption {
          description = "Minimum plausible realtime epoch for clock readiness.";
          type = types.int;
          default = 1704067200; # 2024-01-01T00:00:00Z
        };

        maxEpochSeconds = mkOption {
          description = "Maximum plausible realtime epoch for clock readiness; anchors above this are treated as corrupt.";
          type = types.int;
          default = 2524608000; # 2050-01-01T00:00:00Z
        };
      };
    };
  };

  config = mkIf (loggingStackEnabled && recCfg.enable) {

    ghaf.storagevm.directories = mkIf (clockReadyEnabled && config.ghaf.storagevm.enable) [
      "/var/lib/ghaf/clock-ready"
    ];

    systemd = {
      targets.ghaf-clock-ready = mkIf clockReadyEnabled {
        description = "Ghaf clock readiness barrier";
        requires = [ "ghaf-clock-ready.service" ];
        after = [ "ghaf-clock-ready.service" ];
      };

      services.ghaf-clock-ready = mkIf clockReadyEnabled {
        description = "Wait for clock readiness before persistent sealed logging";
        wantedBy = [ "ghaf-clock-ready.target" ];
        before = [
          "ghaf-clock-ready.target"
          "systemd-journal-flush.service"
          "journal-fss-setup.service"
          "journal-fss-verify.service"
          "alloy.service"
        ];
        after = [ "systemd-journald.service" ];
        wants = [ "systemd-journald.service" ];

        unitConfig = {
          DefaultDependencies = false;
          RequiresMountsFor = [ "/var/lib/ghaf/clock-ready" ];
        };

        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
          TimeoutStartSec = "${toString (recCfg.clockReady.maxWaitSeconds + 30)}s";
          ExecStart = lib.getExe ghafClockReady;
        };
      };

      # Time-sync wait, ordered AFTER networking/timesyncd and BEFORE FSS setup,
      # but deliberately not before systemd-journal-flush, so the early flush only
      # waits on the fast clock-readiness barrier and never on the NTP timeout.
      services.ghaf-clock-sync = mkIf clockReadyEnabled {
        description = "Wait for time synchronization before FSS sealing activation";
        wantedBy = [ "multi-user.target" ];
        after = [
          "ghaf-clock-ready.service"
          "network-online.target"
          "systemd-timesyncd.service"
        ];
        wants = [ "network-online.target" ];
        before = [
          "journal-fss-setup.service"
          "journal-fss-verify.service"
        ];

        unitConfig = {
          RequiresMountsFor = [ "/var/lib/ghaf/clock-ready" ];
        };

        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
          TimeoutStartSec = "${toString (effectiveSyncWaitSeconds + 30)}s";
          ExecStart = lib.getExe ghafClockSync;
        };
      };

      services.systemd-journal-flush = mkIf clockReadyEnabled {
        after = [ "ghaf-clock-ready.service" ];
        requires = [ "ghaf-clock-ready.service" ];
      };

      # Watcher: detects realtime jumps by comparing realtime vs monotonic progression
      services.ghaf-clock-jump-watcher = {
        description = "Detect realtime clock jumps and trigger journald/log-forwarder recovery";
        wantedBy = [ "multi-user.target" ];
        after =
          lib.optionals clockReadyEnabled [ "ghaf-clock-ready.service" ]
          ++ lib.optionals fssActivationEnabled [ "journal-fss-setup.service" ];
        wants =
          lib.optionals clockReadyEnabled [ "ghaf-clock-ready.service" ]
          ++ lib.optionals fssActivationEnabled [ "journal-fss-setup.service" ];

        serviceConfig = {
          Type = "simple";
          Restart = "always";
          RestartSec = 2;
          ExecStart = lib.getExe ghafClockJumpWatcher;
        };
      };

      services.ghaf-journal-alloy-recover = {
        description = "Recover journald/log-forwarder after time jump";
        after =
          lib.optionals clockReadyEnabled [ "ghaf-clock-ready.service" ]
          ++ lib.optionals fssActivationEnabled [ "journal-fss-setup.service" ];
        wants =
          lib.optionals clockReadyEnabled [ "ghaf-clock-ready.service" ]
          ++ lib.optionals fssActivationEnabled [ "journal-fss-setup.service" ];

        unitConfig = {
          StartLimitIntervalSec = "0";
        };

        serviceConfig = {
          Type = "oneshot";
          ExecStart = lib.getExe ghafJournalAlloyRecover;
        };
      };

      services.alloy = mkIf (clockReadyEnabled && config.services.alloy.enable) {
        after = [
          "ghaf-clock-ready.service"
          "journal-fss-setup.service"
        ];
        wants = [
          "ghaf-clock-ready.service"
          "journal-fss-setup.service"
        ];
      };

      tmpfiles.rules = [
        # Create persistent journal dir with the standard perms/group.
        "d /var/log/journal 2755 root systemd-journal - -"
        # Repair perms recursively if something messes them up.
        "Z /var/log/journal 2755 root systemd-journal - -"
      ];
    };
  };
}
