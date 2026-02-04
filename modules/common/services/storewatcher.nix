# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  lib,
  pkgs,
  config,
  ...
}:

let
  inherit (lib)
    mkIf
    mkOption
    mkEnableOption
    types
    ;

  cfg = config.ghaf.services.storeWatcher;

  nrbWatch = pkgs.writeShellApplication {
    name = "nrb-watch";
    runtimeInputs = with pkgs; [
      coreutils
      inotify-tools
      systemd
      gnugrep
      procps
      psmisc
    ];

    text = ''
      store=/nix/store
      state=/run/nrb
      profile=/nix/var/nix/profiles/system
      timer_pid_file="$state/timer.pid"

      quiet_seconds=${toString cfg.quietSeconds}
      busy_grace_seconds=${toString cfg.busyGraceSeconds}
      busy_grace_cycles=${toString cfg.busyGraceCycles}
      session_reset_seconds=${toString cfg.sessionResetSeconds}

      mkdir -p "$state"
      : > "$state/last_event"    || true
      : > "$state/last_path"     || true
      : > "$state/session_start" || true
      : > "$state/aborted_for"   || true
      printf '0\n' > "$state/last_event"
      printf '0\n' > "$state/session_start"
      printf '0\n' > "$state/aborted_for"

      # ---------- helpers ----------
      write_atomic() {
        # $1=file, $2=payload (no trailing newline added unless given)
        local f="$1"
        local tmp="$f.$$"
        ${pkgs.coreutils}/bin/printf '%s' "$2" > "$tmp"
        ${pkgs.coreutils}/bin/mv -f "$tmp" "$f"
      }

      read_num() {
        # digits-only, default 0 on empty/err
        local f="$1" n
        n="$(${pkgs.coreutils}/bin/tr -cd '0-9' < "$f" 2>/dev/null || true)"
        [ -n "$n" ] && echo "$n" || echo 0
      }

      read_text() {
        local f="$1"
        ${pkgs.coreutils}/bin/cat "$f" 2>/dev/null || true
      }

      basename_safely() {
        ${pkgs.coreutils}/bin/basename -- "$1" 2>/dev/null || true
      }

      dir_mtime() {
        local p="$1"
        ${pkgs.coreutils}/bin/stat -c %Y -- "$p" 2>/dev/null || echo 0
      }

      log() {
        # $1=prio (debug|info|warning|err), $2=message
        ${pkgs.systemd}/bin/systemd-cat -t nixos-rebuild -p "$1" -- ${pkgs.coreutils}/bin/printf '%s\n' "$2"
      }

      _real_switch_line_since() {
        local since="$1"
        ${pkgs.systemd}/bin/journalctl -u nixos-rebuild-switch-to-configuration --since "@$since" --no-pager \
          | ${pkgs.gnugrep}/bin/grep -F '/bin/switch-to-configuration' \
          | ${pkgs.coreutils}/bin/tail -n 1
      }

      maybe_success() {
        # $1=session_start, $2=pkg (for logging)
        local started="$1" pkg="$2"

        # Success 1: switch-to-configuration in journal
        local swline
        swline="$(_real_switch_line_since "$started" || true)"
        if [ -n "$swline" ]; then
          log info "store-copy-session ok: pkg=$pkg switch-to-configuration observed since @$started :: $swline"
          write_atomic "$state/session_start" "0"
          write_atomic "$state/aborted_for" "0"
          return 0
        fi

        # Success 2: system profile advanced
        local prof_target prof_ts
        prof_target="$(${pkgs.coreutils}/bin/readlink -f "$profile" || true)"
        if [ -n "$prof_target" ]; then
          prof_ts="$(${pkgs.coreutils}/bin/stat -c %Y "$prof_target" || echo 0)"
          if [ "$prof_ts" -ge "$started" ]; then
            log info "store-copy-session ok: pkg=$pkg profile advanced (ts=@$prof_ts >= @$started)"
            write_atomic "$state/session_start" "0"
            write_atomic "$state/aborted_for" "0"
            return 0
          fi
        fi
        return 1
      }

      # Restart session to the latest event (new dir observed).
      restart_session_to_latest() {
        local last_ts new_path new_pkg
        last_ts="$(read_num "$state/last_event")"
        new_path="$(read_text "$state/last_path")"
        new_pkg="$(basename_safely "$new_path")"
        [ -n "$new_pkg" ] || new_pkg="unknown"
        write_atomic "$state/session_start" "$last_ts"
        write_atomic "$state/aborted_for" "0"
        log info "store-copy-session start ts=@$last_ts pkg=$new_pkg (resumed)"
      }

      # Restart session based on directory mtime progress (even without a new top-level store dir).
      restart_session_to_mtime() {
        # $1=edge_path, $2=new_mtime
        local edge_path="$1" new_ts="$2" pkg
        pkg="$(basename_safely "$edge_path")"
        [ -n "$pkg" ] || pkg="unknown"
        write_atomic "$state/last_event" "$new_ts"
        write_atomic "$state/last_path" "$edge_path"
        write_atomic "$state/session_start" "$new_ts"
        write_atomic "$state/aborted_for" "0"
        log info "store-copy-session start ts=@$new_ts pkg=$pkg (hot)"
      }

      timer_worker() {
        # Exactly one of these runs per session. It lives until success/abort/reset.
        while :; do
          local started
          started="$(read_num "$state/session_start")"
          if [ "$started" -eq 0 ]; then
            break  # no active session; nothing to do
          fi

          # Snapshot the current edge timestamp and path (bind the upcoming fire to these)
          local edge_ts edge_path pkg edge_mtime
          edge_ts="$(read_num "$state/last_event")"
          edge_path="$(read_text "$state/last_path")"
          pkg="$(basename_safely "$edge_path")"
          [ -n "$pkg" ] || pkg="unknown"
          edge_mtime="$(dir_mtime "$edge_path")"

          # Wait until quiet_seconds have elapsed with no changes
          while :; do
            local now deadline last nowStart last_path cur_mtime
            now="$(${pkgs.coreutils}/bin/date +%s)"
            deadline=$(( edge_ts + quiet_seconds ))
            if [ "$now" -ge "$deadline" ]; then
              break
            fi
            ${pkgs.coreutils}/bin/sleep 1

            last="$(read_num "$state/last_event")"
            nowStart="$(read_num "$state/session_start")"
            last_path="$(read_text "$state/last_path")"
            cur_mtime="$(dir_mtime "$edge_path")"

            # If any change (ts or path or session), treat as progress and restart immediately.
            if [ "$nowStart" -ne "$started" ] || [ "$last" -ne "$edge_ts" ] || [ "$last_path" != "$edge_path" ]; then
              restart_session_to_latest
              continue 2
            fi

            # Or if the same edge path's mtime increases, treat as progress (hot copy).
            if [ "$cur_mtime" -gt "$edge_mtime" ]; then
              restart_session_to_mtime "$edge_path" "$cur_mtime"
              continue 2
            fi
          done

          log info "store-copy-debug fire: pkg=$pkg started=@$started edge=@$edge_ts last=$(read_num "$state/last_event") nowStart=$(read_num "$state/session_start")"

          # Immediate success check
          if maybe_success "$started" "$pkg"; then
            break
          fi

          # Busy-grace loop: give the current package some time if its mtime keeps advancing.
          local i=0
          while [ "$i" -lt "$busy_grace_cycles" ]; do
            ${pkgs.coreutils}/bin/sleep "$busy_grace_seconds"

            # Re-evaluate progress
            local last nowStart last_path cur_mtime
            last="$(read_num "$state/last_event")"
            nowStart="$(read_num "$state/session_start")"
            last_path="$(read_text "$state/last_path")"
            cur_mtime="$(dir_mtime "$edge_path")"

            # Any new event or path change => restart to latest; cycles reset next pass
            if [ "$nowStart" -ne "$started" ] || [ "$last" -ne "$edge_ts" ] || [ "$last_path" != "$edge_path" ]; then
              restart_session_to_latest
              continue 3
            fi

            # Same dir got new mtime => treat as progress; restart by mtime
            if [ "$cur_mtime" -gt "$edge_mtime" ]; then
              restart_session_to_mtime "$edge_path" "$cur_mtime"
              continue 3
            fi

            log info "store-copy-session busy: pkg=$pkg no new events; checking again in $busy_grace_seconds (cycle $((i+1))/$busy_grace_cycles)"
            i=$((i+1))
          done

          # Final success check after grace, otherwise, abort
          if maybe_success "$started" "$pkg"; then
            break
          fi

          local already
          already="$(read_num "$state/aborted_for")"
          if [ "$already" -ne "$started" ]; then
            log warning "$(${pkgs.coreutils}/bin/printf 'store-copy-session likely aborted: pkg=%s idle after last /nix/store activity (session_start=@%s last_edge=@%s ts=%s)\n' \
              "$pkg" "$started" "$edge_ts" "$(${pkgs.coreutils}/bin/date -Is)")"
            write_atomic "$state/aborted_for" "$started"
            # reset so the next event becomes a fresh session
            write_atomic "$state/session_start" "0"
          else
            log info "store-copy-debug suppress: pkg=$pkg abort already reported for session_start=@$started"
          fi

          # Long idle: clear markers
          local last_ts now2
          last_ts="$(read_num "$state/last_event")"
          now2="$(${pkgs.coreutils}/bin/date +%s)"
          if [ $(( now2 - last_ts )) -ge "$session_reset_seconds" ]; then
            log info "store-copy-debug reset: pkg=$pkg long idle (>=$session_reset_seconds s), clearing session"
            write_atomic "$state/session_start" "0"
            write_atomic "$state/aborted_for" "0"
          fi
        done
      }

      start_timer_once() {
        # Start a single worker if none is running
        if [ -f "$timer_pid_file" ]; then
          local pid
          pid="$(${pkgs.coreutils}/bin/cat "$timer_pid_file" 2>/dev/null || echo 0)"
          if [ "$pid" -gt 0 ] && kill -0 "$pid" 2>/dev/null; then
            return 0
          fi
        fi
        ( timer_worker ) &
        echo $! > "$timer_pid_file"
      }

      cleanup() { rm -f "$timer_pid_file" 2>/dev/null || true; }
      trap cleanup EXIT INT TERM

      # Main watcher
      while read -r t path; do
        if [ -d "$path" ]; then
          # Atomically record the latest event timestamp AND the path
          write_atomic "$state/last_event" "$t"
          write_atomic "$state/last_path" "$path"

          current="$(read_num "$state/session_start")"
          if [ "$current" -eq 0 ]; then
            write_atomic "$state/session_start" "$t"
            current="$t"
            write_atomic "$state/aborted_for" "0"
            log info "store-copy-session start ts=@$current pkg=$(basename_safely "$path")"
            start_timer_once
          else
            log info "store-copy-debug evt: dir=$path t=@$t sess_start=@$current pkg=$(basename_safely "$path")"
          fi
        fi
      done < <(${pkgs.inotify-tools}/bin/inotifywait -m -e create -e moved_to --format '%T %w%f' --timefmt '%s' "$store")
    '';
  };
in
{
  _file = ./storewatcher.nix;

  options.ghaf.services.storeWatcher = {
    enable = mkEnableOption "monitoring of /nix/store for nixos-rebuild copy sessions and flagging interruptions";
    quietSeconds = mkOption {
      type = types.ints.unsigned;
      default = 60;
      description = "Idle window after the last store event to consider the session quiet.";
    };
    busyGraceSeconds = mkOption {
      type = types.ints.unsigned;
      default = 60;
      description = "Extra wait per grace cycle while checking for directory mtime progress.";
    };
    busyGraceCycles = mkOption {
      type = types.ints.unsigned;
      default = 5;
      description = "How many busy-grace cycles to allow (busyGraceCycles * busyGraceSeconds).";
    };
    sessionResetSeconds = mkOption {
      type = types.ints.unsigned;
      default = 1800;
      description = "If idle this long since last event, clear session markers.";
    };
  };

  config = mkIf cfg.enable {
    systemd.services."nixos-rebuild-watch" = {
      description = "Continuously watch /nix/store for copy sessions and detect interrupted nixos-rebuild";
      wantedBy = [ "multi-user.target" ];
      after = [ "local-fs.target" ];
      serviceConfig = {
        Type = "simple";
        ExecStart = "${nrbWatch}/bin/nrb-watch";
        Restart = "always";
        RestartSec = "2s";
      };
    };
  };
}
