# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  config,
  lib,
  options,
  pkgs,
  ...
}:
let
  cfg = config.ghaf.logging.server;
  startup = cfg.startupLogImport;
  directory = "/var/lib/ghaf-startup-log-import";
in
{
  _file = ./startup-log-import.nix;

  options.ghaf.logging.server.startupLogImport = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = pkgs.stdenv.hostPlatform.isAarch64;
      defaultText = lib.literalExpression "pkgs.stdenv.hostPlatform.isAarch64";
      description = "Requeue this machine's startup records older than Alloy's 15-minute limit once after clock synchronization.";
    };
  };

  config = lib.mkIf (startup.enable && (cfg.enable || config.ghaf.logging.journalClient.enable)) {
    assertions = [
      {
        assertion = config.ghaf.time.enable && config.ghaf.time.requireSync;
        message = "Startup log import requires the Ghaf clock gate on each log producer.";
      }
    ];

    systemd.services.ghaf-startup-log-import = {
      description = "Import old startup logs through Alloy";
      wantedBy = [ "multi-user.target" ];
      requires = [ "ghaf-clock-synced.target" ];
      after = [
        "ghaf-clock-synced.target"
        "systemd-journald.service"
        "systemd-tmpfiles-setup.service"
      ];
      path = [ pkgs.systemd ];
      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${pkgs.python3}/bin/python3 ${./startup-log-import.py} --libsystemd ${lib.getLib pkgs.systemd}/lib/libsystemd.so.0";
        # journalctl --sync requires root to acknowledge the completed batch.
        User = "root";
        Group = "systemd-journal";
        CapabilityBoundingSet = [ ];
        StateDirectory = "ghaf-startup-log-import";
        StateDirectoryMode = "0750";
        UMask = "0027";
        TimeoutStartSec = "infinity";
        MemoryMax = "192M";
        CPUQuota = "25%";
        # Replaying a boot must not exhaust journald's per-service rate limit.
        LogRateLimitIntervalSec = 0;
        NoNewPrivileges = true;
        ProtectSystem = "strict";
        ProtectHome = true;
        ProtectClock = true;
        PrivateTmp = true;
        PrivateDevices = true;
      };
    };

    ghaf.storagevm = lib.optionalAttrs (options ? ghaf.storagevm.directories) {
      directories = lib.mkIf config.ghaf.storagevm.enable [ directory ];
    };
  };
}
