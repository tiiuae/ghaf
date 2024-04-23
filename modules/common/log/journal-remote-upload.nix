# Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{pkgs, ...}: let
  log-vm-ip-port = "192.168.101.66:19532";
in {
  users.users.systemd-journal-upload = {
    isSystemUser = true;
    group = "systemd-journal-upload";
  };
  users.groups.systemd-journal-upload = {};
  users.users.systemd-journal-upload.extraGroups = ["systemd-journal"];

  systemd.services.systemd-journal-upload = {
    description = "Service to upload journal logs to log-vm";
    enable = true;
    after = ["network-online.target"];
    serviceConfig = {
      #ExecStart = "${pkgs.systemd}/lib/systemd/systemd-journal-upload --save-state -u http://${log-vm-ip-port}";
      ExecStart = "${pkgs.systemd}/lib/systemd/systemd-journal-upload -u http://${log-vm-ip-port}";
      User = "systemd-journal-upload";
      Restart = "on-failure";
      RestartSec = "1";
    };

    wantedBy = ["multi-user.target"];
  };
}
