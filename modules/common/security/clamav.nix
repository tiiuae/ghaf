# Copyright 2025 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.ghaf.security.clamav;
  inherit (lib)
    concatStringsSep
    getExe
    hasAttr
    mkEnableOption
    mkIf
    mkOption
    optionalAttrs
    optionals
    types
    ;

  clamavMonitor = pkgs.writeShellApplication {
    name = "clamav-monitor";
    runtimeInputs = [
      config.services.clamav.package
      pkgs.findutils
    ];
    text = ''
      # Script to do initial scan and monitor directories for changes clamonacc on 'watchDirectories'.

      # Note: The '--move' and '--copy' options use rename and do not reliably work for virtiofs shares,
      # even though a fallback option appears to work with clamonacc. However, we rely on our clamav virus
      # event handler to quarantine and remove infected files, so we do not use these options here.

      scan_file() {
        local file="$1"
        local exit_code=0

        # Double check that the file still exists
        [[ -f "$file" ]] || return 1

        # Scan the file with clamdscan
        clamdscan --fdpass --quiet --infected "$file" || exit_code=$?

        # Check errors
        [[ $exit_code -eq 1 ]] &&  echo "Infected file found: $file"
        [[ $exit_code -gt 1 ]] &&  echo "Clamdscan error (code $exit_code) while scanning $file." >&2
      }
      export -f scan_file

      # Convert watchDirectories to an array
      IFS=' ' read -r -a watch_dirs <<< "${concatStringsSep " " cfg.watchDirectories}"

      # Initial scan on startup
      echo "Starting initial scan of directories: ''${watch_dirs[*]}"
      for dir in "''${watch_dirs[@]}"; do
        [[ -d "$dir" ]] || { echo "Warning: Watch directory $dir does not exist or is not a directory." >&2; continue; }
        # shellcheck disable=SC2016
        find "$dir" -type f -exec /bin/sh -c 'scan_file "$0"' {} \;
      done

      # Continuous on-access monitoring
      echo "Starting to monitor directories with clamonacc..."
      clamonacc \
        --wait \
        --fdpass \
        --allmatch \
        --foreground
    '';
  };

  clamavEventHandler = pkgs.writeShellApplication {
    name = "clamav-event-handler";
    runtimeInputs = [
      pkgs.coreutils
    ];
    text = ''
      # Custom ClamAV virus event handler script
      [[ $# -ne 2 ]] && { echo "Usage: $0 <filename> <virusname>" >&2; exit 1; }
      [[ -z "$1" || -z "$2" ]] && { echo "Both filepath and virusname must be provided." >&2; exit 1; }

      CLAM_VIRUSEVENT_FILENAME="$1"
      CLAM_VIRUSEVENT_VIRUSNAME="$2"
      alert="VIRUSALERT=Malware $CLAM_VIRUSEVENT_VIRUSNAME was detected in file $CLAM_VIRUSEVENT_FILENAME "

      # Force file quarantine as root in case the previous client options failed
      if [ -f "$CLAM_VIRUSEVENT_FILENAME" ]; then
        cp -f "$CLAM_VIRUSEVENT_FILENAME" "${cfg.quarantineDirectory}/$(basename "$CLAM_VIRUSEVENT_FILENAME")"
        rm -f "$CLAM_VIRUSEVENT_FILENAME"
        alert+="and quarantined."
      else
        alert+="but could not be quarantined (file not found)."
      fi

      echo "$alert"
    '';
  };

in
{
  options.ghaf.security.clamav = {
    enable = mkEnableOption "Enable ClamAV antivirus service.";
    scanDirectories = mkOption {
      type = types.listOf types.str;
      default = [
        "/home"
        "/var"
        "/tmp"
        "/etc"
      ];
      description = ''
        Directories to scan with clamdscan in the defined interval.
        For real-time (on-access) monitoring, use the 'watchDirectories' option.
      '';
      example = [
        "/home"
        "/var"
        "/tmp"
        "/etc"
      ];
    };
    quarantineDirectory = mkOption {
      type = types.str;
      default = "/var/lib/clamav/quarantine";
      description = "Directory to move infected files to. This directory is automatically excluded from scans.";
      example = "/var/lib/clamav/quarantine";
    };
    excludeDirectories = mkOption {
      type = types.listOf types.str;
      default = [ ];
      description = ''
        Directories to exclude from regular scans. This is useful for sub-directories of scanDirectories or watchDirectories
        that contain large or frequently changing files, or are otherwise not suitable for scanning.
      '';
      example = [
        "/var/cache"
      ];
    };
    watchDirectories = mkOption {
      type = types.listOf types.str;
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
  };
  config = mkIf cfg.enable {

    ghaf =
      optionalAttrs (hasAttr "graphics" config.ghaf.profiles) {
        # User notifier for clamav
        services.log-notifier = optionalAttrs config.ghaf.profiles.graphics.enable {
          enable = true;
          events = {
            "clamav-alert" = {
              unit = "clamav-daemon.service";
              filter = "VIRUSALERT";
              title = "Malware Detected";
              criticality = "critical";
              formatter = ''
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
      }
      // optionalAttrs (hasAttr "storagevm" config.ghaf) {
        # Persistent storage
        storagevm.directories = [
          {
            directory = "/var/lib/clamav";
            user = "clamav";
            group = "clamav";
            mode = "0700";
          }
          {
            directory = "/var/log/clamav";
            user = "clamav";
            group = "clamav";
            mode = "0700";
          }
          {
            directory = "${cfg.quarantineDirectory}";
            user = "clamav";
            group = "clamav";
            mode = "0700";
          }
        ];
      };

    # ClamAV configuration
    services.clamav = {

      # Regular scanning service
      scanner = {
        enable = true;
        interval = "hourly";
        inherit (cfg) scanDirectories;
      };

      # Database updater
      updater = {
        enable = true;
        interval = "daily";
        frequency = 24;
      };

      # Third-party updates
      fangfrisch = {
        enable = true;
        interval = "daily";
      };

      # ClamAV Daemon
      daemon = {
        enable = true;
        settings = {
          VirusEvent = ''
            /run/wrappers/bin/sudo ${getExe clamavEventHandler} "$CLAM_VIRUSEVENT_FILENAME" %v
          '';
          LogFile = "/var/log/clamav/clamd.log";
          LogTime = true;
          LogClean = false;
          LogSyslog = true;
          LogVerbose = false;
          LogFileMaxSize = "20M";
          ExtendedDetectionInfo = true;
          OnAccessPrevention = cfg.watchDirectories != [ ];
          OnAccessExcludeUname = "clamav";
          OnAccessExcludeRootUID = true;
          OnAccessRetryAttempts = 3;
          OnAccessIncludePath = "${concatStringsSep " " cfg.watchDirectories}";
          OnAccessExcludePath = "${cfg.quarantineDirectory} ${concatStringsSep " " cfg.excludeDirectories}";
          ExcludePath = "${cfg.quarantineDirectory} ${concatStringsSep " " cfg.excludeDirectories}";
        };
      };
    };

    # Run clamav virus event handler as root
    security.sudo.extraConfig = ''
      clamav ALL=(root) NOPASSWD: ${getExe clamavEventHandler}
    '';

    # Clamav monitor service
    systemd = {
      services.clamav-daemon = {
        # Prevent service failure on first boot
        after = optionals (hasAttr "setup-ghaf-user" config.systemd.services) [ "setup-ghaf-user.service" ];
        serviceConfig = {
          Restart = "always";
          RestartSec = "5s";
        };
      };
    }
    // optionalAttrs (cfg.watchDirectories != [ ]) {
      paths.clamav-monitor = {
        description = "ClamAV Socket Monitor";
        wantedBy = [ "multi-user.target" ];
        pathConfig.PathExists = "/run/clamav/clamd.ctl";
      };
      services.clamav-monitor = {
        description = "ClamAV monitor service";
        documentation = [ "man:clamonacc(8)" ];
        serviceConfig = {
          ExecStart = "${getExe clamavMonitor}";
          Restart = "always";
          RestartSec = "3s";
          Slice = "system-clamav.slice";
        };
      };
    };

  };
}
