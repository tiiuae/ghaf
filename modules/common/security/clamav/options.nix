# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# ClamAV option definitions
#
{ lib, ... }:
{
  _file = ./options.nix;

  options.ghaf.security.clamav = {
    enable = lib.mkEnableOption "ClamAV antivirus service";

    daemon = {
      enable = lib.mkEnableOption "ClamAV daemon (clamd) for real-time scanning";
      alertOnLimitsExceeded = lib.mkEnableOption ''
        flag files exceeding size/recursion limits as 'Heuristics.Limits.Exceeded'.
        When disabled (default), files exceeding MaxFileSize (2GB), MaxScanSize (4GB),
        or other limits are silently allowed through without scanning
      '';
    };

    proxy = {
      enable = lib.mkEnableOption "clamd-vproxy on host to provide scanning proxy via vsock";
      cid = lib.mkOption {
        type = lib.types.int;
        default = 2;
        description = "Vsock CID of the proxy (defaults to host: 2).";
      };
      port = lib.mkOption {
        type = lib.types.port;
        default = 3400;
        description = "Vsock port where clamd-vproxy listens for guest connections.";
      };
    };

    quarantineDirectory = lib.mkOption {
      type = lib.types.str;
      default = "/var/lib/clamav/quarantine";
      description = "Directory to move infected files detected by scanning.";
    };

    scan = {
      on-access = {
        enable = lib.mkEnableOption "on-access scanning via clamonacc (fanotify-based, blocks file access until scanned)";
        directories = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = [ ];
          description = ''
            Directories to monitor and scan with clamdscan on change. This enables real-time (on-access) scanning of files.
            This feature may have a noticable performance impact, especially when monitoring directories with
            high I/O activity. Consult the ClamAV documentation for details.
          '';
          example = [
            "/home"
            "/var"
          ];
        };
        excludeDirectories = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = [ ];
          description = "Directories to exclude from on-access scans.";
          example = [ "/var/cache" ];
        };
      };
      on-modify = {
        enable = lib.mkEnableOption "on-modify scanning via inotify trigger";
        directories = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = [ ];
          description = ''
            Directories to monitor and scan with clamd on modification, using inotifywait monitoring 'close_write' and 'moved_to' events.
          '';
          example = [
            "/home"
            "/var"
          ];
        };
        excludeDirectories = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = [ ];
          description = "Directories to exclude from on-modify monitoring.";
          example = [ "/var/cache" ];
        };
        clientConfig = {
          cid = lib.mkOption {
            type = lib.types.int;
            default = 2;
            description = "Vsock CID of the remote scanner when daemon is not local. Default is 2 (host).";
          };
          port = lib.mkOption {
            type = lib.types.port;
            default = 3400;
            description = "Vsock port for connecting to clamd-vproxy when daemon is not local.";
          };
        };
      };
      on-schedule = {
        enable = lib.mkEnableOption "scheduled periodic scanning";
        interval = lib.mkOption {
          type = lib.types.str;
          default = "hourly";
          description = ''
            Interval for regular ClamAV scans. See systemd.timer documentation for valid values.
            Uses clamdscan (fast) when daemon is enabled, clamscan (standalone) otherwise.
          '';
          example = "daily";
        };
        directories = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = [ ];
          description = "Directories to scan in the defined interval.";
          example = [
            "/home"
            "/var"
            "/tmp"
            "/etc"
          ];
        };
        excludeDirectories = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = [ ];
          description = "Directories to exclude from scheduled scanning. Only used in standalone mode (without daemon).";
          example = [ "/var/cache" ];
        };
      };
    };

    database = {
      updater = {
        enable = lib.mkEnableOption "automatic ClamAV database updates";
        interval = lib.mkOption {
          type = lib.types.str;
          default = "hourly";
          description = "Interval for ClamAV database updates. See systemd.timer documentation for valid values.";
          example = "daily";
        };
      };
      fangfrisch = {
        enable = lib.mkEnableOption "automatic updates of third-party ClamAV databases via fangfrisch";
        interval = lib.mkOption {
          type = lib.types.str;
          default = "daily";
          description = "Interval for fangfrisch database updates. See systemd.timer documentation for valid values.";
          example = "weekly";
        };
      };
    };
  };
}
