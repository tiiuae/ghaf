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
      systemd
    ];
    text = ''
      stamp="/run/ghaf-journal-alloy-recover.stamp"
      now="$(date +%s)"
      cooldown="${toString recCfg.cooldownSeconds}"

      if [ -e "$stamp" ]; then
        last="$(cat "$stamp" 2>/dev/null || echo 0)"
        if [ "$((now-last))" -lt "$cooldown" ]; then
          exit 0
        fi
      fi
      echo "$now" > "$stamp"

      systemd-tmpfiles --create --prefix /var/log/journal
      systemctl restart systemd-journald.service
      systemctl restart alloy.service
    '';
  };
in
{
  _file = ./common.nix;

  # Creating logging configuration options needed across the host and vms
  options.ghaf.logging = {
    enable = mkEnableOption "logging service (grafana alloy client uploading journal logs to admin-vm)";

    listener.address = mkOption {
      description = ''
        Listener address will be used where log producers will
        push logs and where admin-vm alloy.service will be
        keep on listening or receiving logs.
      '';
      type = types.str;
      default = "";
    };

    listener.port = mkOption {
      description = ''
        Listener port for the logproto endpoint which will be
        used to receive logs from different log producers.
        Also this port value will be used to open the port in
        the admin-vm firewall.
      '';
      type = types.port;
      default = 9999;
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
    };

    recovery = {
      enable = mkEnableOption "journald/alloy recovery after realtime clock jumps";

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

  config = mkIf (config.ghaf.logging.enable && recCfg.enable) {

    systemd = {
      # Watcher: detects realtime jumps by comparing realtime vs monotonic progression
      services.ghaf-clock-jump-watcher = {
        description = "Detect realtime clock jumps and trigger journald/alloy recovery";
        wantedBy = [ "multi-user.target" ];

        serviceConfig = {
          Type = "simple";
          Restart = "always";
          RestartSec = 2;
          ExecStart = lib.getExe ghafClockJumpWatcher;
        };
      };

      services.ghaf-journal-alloy-recover = {
        description = "Recover journald/alloy after time jump";

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
        # Repair perms recursively if something messes them up.
        "Z /var/log/journal 2755 root systemd-journal - -"
      ];
    };
  };
}
