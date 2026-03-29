# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.ghaf.security.clamav;

  # Import scripts
  scripts = import ./scripts.nix { inherit config lib pkgs; };
in
{
  _file = ./services.nix;

  config = lib.mkIf cfg.enable {
    assertions = [
      # on-access: requires directories and local daemon (clamonacc uses fanotify)
      {
        assertion = cfg.scan.on-access.enable -> cfg.scan.on-access.directories != [ ];
        message = "ghaf-clamav: scan.on-access.enable requires scan.on-access.directories to be set";
      }
      {
        assertion = cfg.scan.on-access.enable -> cfg.daemon.enable;
        message = "ghaf-clamav: scan.on-access.enable requires daemon.enable (clamonacc needs clamd)";
      }
      # on-modify: requires directories (can use local daemon or remote via vsock)
      {
        assertion = cfg.scan.on-modify.enable -> cfg.scan.on-modify.directories != [ ];
        message = "ghaf-clamav: scan.on-modify.enable requires scan.on-modify.directories to be set";
      }
      # on-schedule: requires directories; standalone mode (no daemon) needs database updater
      {
        assertion = cfg.scan.on-schedule.enable -> cfg.scan.on-schedule.directories != [ ];
        message = "ghaf-clamav: scan.on-schedule.enable requires scan.on-schedule.directories to be set";
      }
      {
        assertion = cfg.scan.on-schedule.enable && !cfg.daemon.enable -> cfg.database.updater.enable;
        message = "ghaf-clamav: scan.on-schedule without daemon requires database.updater.enable (standalone clamscan needs database)";
      }
      # proxy: requires local daemon to forward requests
      {
        assertion = cfg.proxy.enable -> cfg.daemon.enable;
        message = "ghaf-clamav: proxy.enable requires daemon.enable (clamd-vproxy needs clamd)";
      }
    ];

    # Create clamav user/group when daemon is not enabled
    users =
      lib.mkIf
        (
          !cfg.daemon.enable
          && (cfg.scan.on-access.enable || cfg.scan.on-modify.enable || cfg.scan.on-schedule.enable)
        )
        {
          users.clamav = {
            isSystemUser = true;
            group = "clamav";
            description = "ClamAV user";
          };
          groups.clamav = { };
        };

    # ClamAV module configuration (runs on both host and VMs)
    services.clamav = {

      # Regular scanning service
      scanner = lib.mkIf cfg.daemon.enable {
        inherit (cfg.scan.on-schedule) enable interval;
        scanDirectories = cfg.scan.on-schedule.directories;
      };

      # Database updater
      updater = {
        inherit (cfg.database.updater) enable interval;
      };

      # Third-party updates
      fangfrisch = {
        inherit (cfg.database.fangfrisch) enable interval;
      };

      # ClamAV Daemon
      daemon = {
        inherit (cfg.daemon) enable;
        settings = lib.mkIf cfg.daemon.enable (
          {
            AlertExceedsMax = cfg.daemon.alertOnLimitsExceeded;
            LogFile = "/var/log/clamav/clamd.log";
            LogTime = true;
            LogClean = false;
            LogSyslog = true;
            LogVerbose = false;
            LogFileMaxSize = "20M";
            ExtendedDetectionInfo = true;
            ExcludePath = [ cfg.quarantineDirectory ];
            StreamMaxLength = "2G"; # Max data via INSTREAM
            MaxFileSize = "2G"; # Max individual file size
            MaxScanSize = "4G"; # Max cumulative size for archives
          }
          # VirusEvent is needed for on-access (clamonacc) and on-schedule with daemon (clamdscan)
          # Note: may cause duplicate notifications if on-modify is also enabled (clamd-vclient notifies directly)
          // lib.optionalAttrs (cfg.scan.on-access.enable || cfg.scan.on-schedule.enable) {
            VirusEvent = ''
              ${lib.getExe scripts.clamavEventHandler} "$CLAM_VIRUSEVENT_FILENAME" %v
            '';
          }
          // lib.optionalAttrs cfg.scan.on-access.enable {
            OnAccessPrevention = true;
            OnAccessExcludeUname = "clamav";
            OnAccessRetryAttempts = 3;
            OnAccessIncludePath = cfg.scan.on-access.directories;
            OnAccessExcludePath = [
              cfg.quarantineDirectory
            ]
            ++ cfg.scan.on-access.excludeDirectories;
          }
        );
      };
    };

    # Systemd services and configurations
    systemd = lib.mkMerge [

      # Updater - Freshclam: run on boot and persist timer for subsequent runs
      (lib.mkIf cfg.database.updater.enable {
        services.clamav-freshclam = {
          wantedBy = [ "multi-user.target" ];
          serviceConfig.ExecStartPre = [ (lib.getExe scripts.waitForInternet) ];
        };
        timers.clamav-freshclam.timerConfig.Persistent = true;
      })

      # Updater - Fangfrisch: run on boot and persist timer for subsequent runs
      (lib.mkIf cfg.database.fangfrisch.enable {
        services.clamav-fangfrisch = {
          wantedBy = [ "multi-user.target" ];
          serviceConfig.ExecStartPre = [ (lib.getExe scripts.waitForInternet) ];
        };
        timers.clamav-fangfrisch.timerConfig.Persistent = true;
      })

      # Clamav-daemon configuration
      (lib.mkIf cfg.daemon.enable {
        # Custom activation chain: db exists -> socket & daemon
        paths.clamav-daemon = {
          description = "Watch for ClamAV database availability";
          wantedBy = [ "multi-user.target" ];
          pathConfig.PathExists = "/var/lib/clamav/main.cvd";
        };
        sockets.clamav-daemon = {
          wantedBy = lib.mkForce [ ];
          after = [ "systemd-tmpfiles-setup.service" ];
          requires = [ "systemd-tmpfiles-setup.service" ];
        };
        services.clamav-daemon = {
          wantedBy = lib.mkForce [ ];
          serviceConfig = {
            Restart = "on-failure";
            RestartSec = "5s";
          };
        };
      })

      # On-modify monitor service - tracks file modifications via inotify
      (lib.mkIf cfg.scan.on-modify.enable {
        paths.clamav-on-modify-monitor = lib.mkIf (!cfg.daemon.enable) {
          description = "ClamAV on-modify monitor activator";
          wantedBy = [ "multi-user.target" ];
          pathConfig.PathExists = "/dev/vsock";
        };
        services.clamav-on-modify-monitor = {
          description = "ClamAV on-modify monitor service";
          wantedBy = lib.optionals cfg.daemon.enable [ "clamav-daemon.service" ];
          after = lib.optionals cfg.daemon.enable [ "clamav-daemon.service" ];
          bindsTo = lib.optionals cfg.daemon.enable [ "clamav-daemon.service" ];
          serviceConfig = {
            ExecStart = "${lib.getExe scripts.clamavScanner} on-modify";
            Restart = "always";
            RestartSec = "3s";
            Slice = "system-clamav.slice";
          };
        };
      })

      # On-access monitor service
      (lib.mkIf (cfg.daemon.enable && cfg.scan.on-access.enable) {
        services.clamav-on-access-monitor = {
          description = "ClamAV on-access monitor service";
          documentation = [ "man:clamonacc(8)" ];
          wantedBy = [ "clamav-daemon.service" ];
          bindsTo = [ "clamav-daemon.service" ];
          after = [ "clamav-daemon.service" ];
          serviceConfig = {
            ExecStart = "${lib.getExe scripts.clamavScanner} on-access";
            Restart = "always";
            RestartSec = "3s";
            Slice = "system-clamav.slice";
          };
        };
      })

      # Standalone on-schedule service (when daemon is not enabled)
      (lib.mkIf (cfg.scan.on-schedule.enable && !cfg.daemon.enable) {
        timers.clamav-on-schedule = {
          description = "ClamAV scheduled scanner timer";
          wantedBy = [ "timers.target" ];
          timerConfig = {
            OnCalendar = cfg.scan.on-schedule.interval;
            Persistent = true;
          };
        };
        services.clamav-on-schedule = {
          description = "ClamAV scheduled scanner service";
          serviceConfig = {
            Type = "oneshot";
            ExecStart = "${lib.getExe scripts.clamavScanner} on-schedule";
            Slice = "system-clamav.slice";
          };
        };
      })

      # ClamAV vsock proxy service (bridge to clients via vsock)
      (lib.mkIf cfg.proxy.enable {
        services.clamd-vproxy = {
          description = "ClamAV vsock proxy for file scanning";
          wantedBy = [ "clamav-daemon.service" ];
          bindsTo = [ "clamav-daemon.service" ];
          after = [ "clamav-daemon.service" ];
          serviceConfig = {
            ExecStart = "${lib.getExe' pkgs.ghaf-virtiofs-tools "clamd-vproxy"} --cid ${toString cfg.proxy.cid} --port ${toString cfg.proxy.port}";
            Restart = "always";
            RestartSec = "3s";
            Slice = "system-clamav.slice";
          };
        };
      })

      # User notification service
      (lib.mkIf
        (
          cfg.scan.on-access.enable
          || cfg.scan.on-schedule.enable
          || cfg.scan.on-modify.enable
          || cfg.daemon.enable
        )
        {
          sockets.clamav-notify = {
            description = "ClamAV notification socket";
            after = [ "systemd-tmpfiles-setup.service" ];
            wantedBy = [ "sockets.target" ];
            socketConfig = {
              ListenStream = "/run/clamav/notify.sock";
              SocketUser = "clamav";
              SocketGroup = "clamav";
              SocketMode = "0600";
              Accept = "yes";
            };
          };
          services."clamav-notify@" = {
            description = "ClamAV user notification service";
            serviceConfig = {
              ExecStart = "${lib.getExe scripts.givcNotify}";
              Slice = "system-clamav.slice";
              StandardInput = "socket";
            };
          };
          tmpfiles.rules = [ "d /run/clamav 0755 clamav clamav -" ];
        }
      )
    ];
  };
}
