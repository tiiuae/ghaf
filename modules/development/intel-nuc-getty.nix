# Copyright 2022-2023 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  pkgs,
  config,
  ...
}: {
  config.services.getty.extraArgs = ["115200"];
  config.systemd.services."autovt@ttyUSB0".enable = true;

  # ttyUSB0 service is active as soon as corresponding device appears
  config.services.udev.extraRules = ''
    SUBSYSTEM=="tty", KERNEL=="ttyUSB0", TAG+="systemd", ENV{SYSTEMD_WANTS}+="autovt@ttyUSB0.service"
  '';
}
