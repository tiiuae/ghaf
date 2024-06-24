# Copyright 2024-2025 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  config,
  lib,
  ...
}: let
  cfg = config.ghaf.security.clamav;
in {
  ## Antivirus in Ghaf
  options.ghaf.security.clamav = {
    # Option to enable
    enable = lib.mkOption {
      description = ''
        Enable Clamav antivirus.
      '';
      type = lib.types.bool;
      default = false;
    };

    # Option to enable live update of virus database
    live-update = lib.mkOption {
      description = ''
        Enable live update.
      '';
      type = lib.types.bool;
      default = false;
    };
  };

  config.services.clamav = lib.mkIf cfg.enable {
    # Enable Clamav antivirus daemon
    daemon = {
      enable = true;
      settings = {
        #TODO: write more configuration for Clamav
        #https://linux.die.net/man/5/clamd.conf

        # Uncomment these options to enable logging.
        # LogFile must be writable for the user running daemon.
        # A full path is required.

        #LogFile = "/tmp/clamd.log";
        #LogFileMaxSize = "2M";
        #LogTime = "yes";
        #LogRotate = "yes";
        #ExtendedDetectionInfo = "yes";

        # Always block cloaked URLs, even if URL isn't in database.
        # This can lead to false positives.
        PhishingAlwaysBlockCloak = "no";

        # Allow heuristic match to take precedence.
        # When enabled, if a heuristic scan (such as phishingScan) detects
        # a possible virus/phish it will stop scan immediately. Recommended, saves CPU
        # scan-time.
        # When disabled, virus/phish detected by heuristic scans will be reported only at
        # the end of a scan. If an archive contains both a heuristically detected
        # virus/phish, and a real malware, the real malware will be reported
        HeuristicScanPrecedence = "yes";

        # Enable the Data Loss Prevention module
        StructuredDataDetection = "yes";

        # Stop daemon when libclamav reports out of memory condition.
        ExitOnOOM = "yes";

        # With this option clamav will try to detect broken executables (both PE and
        # ELF) and mark them as Broken.Executable.
        DetectBrokenExecutables = "yes";
      };
    };
    updater = lib.mkIf cfg.live-update {
      # Enable live update of virus database
      enable = true;
      settings = {
        #TODO: write updater configuration
        #https://linux.die.net/man/5/freshclam.conf
      };
      #Update virus database every hour
      interval = "hourly";
      #Update from 12 databases daily
      frequency = 12;
    };
  };
}
