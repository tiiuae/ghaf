# Copyright 2022-2023 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{pkgs, ...}: {
  hardware.opengl = {
    enable = true;
    driSupport = true;
  };

  environment.noXlibs = false;
  environment.systemPackages = with pkgs; [
    weston
    qtemu
  ];

  systemd.services."weston" = {
        description = "Weston Service'";
        wantedBy = [ "multi-user.target" ];
        serviceConfig.Type = "oneshot";
        script = "/run/wrappers/bin/sudo -E ${pkgs.weston}/bin/weston";
        serviceConfig.SyslogIdentifier = "weston";
        requires=["systemd-user-sessions.service"];
        after=["systemd-user-sessions.service"];
        preStart="/run/wrappers/bin/sudo /run/current-system/sw/bin/mkdir -p /run/user/1000\n/run/wrappers/bin/sudo /run/current-system/sw/bin/chown ghaf:ghaf /run/user/1000\n/run/current-system/sw/bin/chmod 0700 /run/user/1000";
      };
}
