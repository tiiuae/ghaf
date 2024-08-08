# Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# Original source: https://gitlab.com/distrosync/nixos/-/blob/master/modules/journal/journal-remote.nix
# Run this on your development machine, or a virtual machine to collect logs.
{
  config,
  lib,
  ...
}: let
  # Ghaf configuration flag
  cfg = config.ghaf.systemd.withRemoteJournalServer;
in
  with lib; {
    options.ghaf.systemd.withRemoteJournalServer = {
      enable = mkOption {
        description = ''
          Enable remote journaling server for systemd debugging. Note that this option uses
          insecure http and is only intended for local debugging purposes.
        '';
        type = types.bool;
        default = false;
      };
    };

    config = mkIf cfg.enable {
      assertions = [
        {
          assertion = config.ghaf.systemd.withJournal;
          message = ''
            The systemd journal must be enabled when enabling systemd-journal-upload.
            Hint: Set `ghaf.systemd.withJournal` to true.
          '';
        }
        {
          assertion = !config.ghaf.profiles.release.enable;
          message = ''
            This module should never by used in release.
          '';
        }
      ];

      # This configuration is adapted from this service file example:
      # /run/current-system/systemd/example/systemd/system/systemd-journal-remote.service

      # To allow journal-upload clients to access the journal-remote listener
      networking.firewall.allowedTCPPorts = [19532];
      # Create a new user for journal-remote, and use existing systemd-journal group
      users.users.systemd-journal-remote = {
        isSystemUser = true;
        group = "systemd-journal";
      };
      # Create a directory for the remote logs, so that they inherit the ACLs of the parent /var/log/journal directory.
      # This is probably not necessary, but it is part of trying to debug journald configs not applying to remote journal files.
      systemd.tmpfiles.rules = ["d /var/log/journal/remote 755 systemd-journal-remote systemd-journal"];

      systemd.services.systemd-journal-remote = {
        enable = true;
        description = "Journal Remote Sink Service";
        documentation = ["man:systemd-journal-remote(8)" "man:journal-remote.conf(5)"];
        requires = ["systemd-journal-remote.socket"];

        serviceConfig = {
          ExecStart = "/run/current-system/systemd/lib/systemd/systemd-journal-remote --listen-http=-3 --output=/var/log/journal/remote/";
          LockPersonality = "yes";
          LogsDirectory = "journal/remote";
          MemoryDenyWriteExecute = "yes";
          NoNewPrivileges = "yes";
          PrivateDevices = "yes";
          PrivateNetwork = "yes";
          PrivateTmp = "yes";
          ProtectControlGroups = "yes";
          ProtectHome = "yes";
          ProtectHostname = "yes";
          ProtectKernelModules = "yes";
          ProtectKernelTunables = "yes";
          ProtectSystem = "strict";
          RestrictAddressFamilies = "AF_UNIX AF_INET AF_INET6";
          RestrictNamespaces = "yes";
          RestrictRealtime = "yes";
          RestrictSUIDSGID = "yes";
          SystemCallArchitectures = "native";
          User = "systemd-journal-remote";
          Group = "systemd-journal";
          WatchdogSec = "10";
          # If there are many split up journal files we need a lot of fds to access them all in parallel.
          LimitNOFILE = "524288";
        };
        # Added so that the service will start automatically.
        # Possibly also add a "Restart" to the serviceConfig if it doesn't recover from failures.
        wantedBy = ["multi-user.target"];
      };

      systemd.sockets.systemd-journal-remote = {
        enable = true;
        description = "Journal Remote Sink Socket";
        listenStreams = ["19532"];
        wantedBy = ["sockets.target"];
      };
    };
  }
