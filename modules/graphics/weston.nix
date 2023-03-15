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
  ];
}
