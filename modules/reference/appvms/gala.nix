# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
{
  pkgs,
  config,
  ...
}:
{
  gala = {
    ramMb = 1536;
    cores = 2;
    bootPriority = "low";
    borderColor = "#027d7b";
    vtpm = {
      enable = true;
      runInVM = config.ghaf.virtualization.storagevm-encryption.enable;
      basePort = 9140;
    };
    applications = [
      {
        name = "GALA";
        description = "Secure Android-in-the-Cloud";
        packages = [ pkgs.gala ];
        icon = "distributor-logo-android";
        command = "gala --enable-features=UseOzonePlatform --ozone-platform=wayland";
      }
    ];
  };
}
