# Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# Original configuration source: https://gitlab.com/distrosync/nixos/-/blob/master/modules/journal/journal-upload.nix
{
  config,
  lib,
  ...
}: let
  # Ghaf configuration flag
  cfg = config.ghaf.systemd.withRemoteJournal;
in
  with lib; {
    options.ghaf.systemd.withRemoteJournal = {
      enable = mkOption {
        description = ''
          Enable remote journaling for systemd debugging. Note that this option uses
          insecure http and is only intended for local debugging purposes.
        '';
        type = types.bool;
        default = false;
      };
      debugServerIpv4 = mkOption {
        description = "The IPv4 address of the debug server to which the journal should be uploaded.";
        type = types.str;
        default = "192.168.101.1";
        example = "192.168.101.1";
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
          assertion = cfg.debugServerIpv4 != "";
          message = ''
            The debug server IP address must be set when enabling systemd-journal-upload.
            Hint: Set `ghaf.systemd.withRemoteJournal.debugServerIpv4` to the IP address of the debug server.
          '';
        }
        {
          assertion = !config.ghaf.profiles.release.enable;
          message = ''
            This module should never by used in release.
          '';
        }
      ];

      # Systemd >= 255 / unstable implementation
      # services.journald.upload = {
      #   enable = true;
      #   settings = {
      #     Upload.URL = "http://${cfg.debugServerIpv4}:19532";
      #   };
      # };

      users = {
        users.systemd-journal-upload = {
          isSystemUser = true;
          group = "systemd-journal-upload";
        };
        groups.systemd-journal-upload = {};
      };

      systemd.services.systemd-journal-upload = {
        enable = true;
        description = "Journal Remote Upload Service";
        documentation = ["man:systemd-journal-upload(8)"];
        wants = ["network-online.target"];
        after = ["network-online.target"];
        wantedBy = ["multi-user.target"];
        serviceConfig = {
          ExecStart = "/run/current-system/systemd/lib/systemd/systemd-journal-upload --save-state -u http://${cfg.debugServerIpv4}:19532";
          DynamicUser = "yes";
          LockPersonality = "yes";
          MemoryDenyWriteExecute = "yes";
          PrivateDevices = "yes";
          ProtectControlGroups = "yes";
          ProtectHome = "yes";
          ProtectHostname = "yes";
          ProtectKernelModules = "yes";
          ProtectKernelTunables = "yes";
          Restart = "always";
          RestartSec = "10";
          RestrictAddressFamilies = "AF_UNIX AF_INET AF_INET6";
          RestrictNamespaces = "yes";
          RestrictRealtime = "yes";
          StateDirectory = "systemd/journal-upload";
          SupplementaryGroups = "systemd-journal";
          SystemCallArchitectures = "native";
          User = "systemd-journal-upload";
          WatchdogSec = "10";
          # If there are many split up journal files we need a lot of fds to access them all in parallel.
          LimitNOFILE = "524288";
        };
      };

      # Add route to enable remote logging (for debugging only)
      systemd.network.networks."10-virbr0".routes =
        if (config.system.name == "ghaf-host")
        then [{routeConfig.Gateway = "192.168.101.1";}]
        else [];
    };
  }
