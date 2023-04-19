# Copyright 2022-2023 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{pkgs, ...}: {
  fonts.fonts = with pkgs; [
    fira-code
    hack-font
  ];
}
