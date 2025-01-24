# Copyright 2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
{
  pkgs,
  ...
}:
{
  name = "gala";
  ramMb = 1536;
  cores = 2;
  borderColor = "#027d7b";
  applications = [
    {
      name = "GALA";
      description = "Secure Android-in-the-Cloud";
      packages = [ pkgs.gala-app ];
      icon = "distributor-logo-android";
      command = "gala --enable-features=UseOzonePlatform --ozone-platform=wayland";
    }
  ];
}
