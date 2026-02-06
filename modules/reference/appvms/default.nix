# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# Reference App VMs Module
#
# This module imports all reference App VM definitions as proper NixOS modules.
# Each App VM can be individually enabled/disabled.
#
# Usage:
#   ghaf.reference.appvms.enable = true;  # Enable all reference appvms
#   ghaf.reference.appvms.chromium.enable = false;  # Disable specific one
#
{
  config,
  lib,
  ...
}:
let
  cfg = config.ghaf.reference.appvms;
in
{
  _file = ./default.nix;

  imports = [
    ./business.nix
    ./chromium.nix
    ./comms.nix
    ./flatpak.nix
    ./gala.nix
    ./google-chrome.nix
    ./zathura.nix
  ];

  options.ghaf.reference.appvms.enable = lib.mkEnableOption "Enable the Ghaf reference appvms module";

  config = lib.mkIf cfg.enable {
    # Enable the main appvm module
    ghaf.virtualization.microvm.appvm.enable = true;

    # disable all by default, users can enable individually
    ghaf.reference.appvms = {
      business.enable = lib.mkDefault false;
      chromium.enable = lib.mkDefault false;
      comms.enable = lib.mkDefault false;
      flatpak.enable = lib.mkDefault false;
      gala.enable = lib.mkDefault false;
      chrome.enable = lib.mkDefault false;
      zathura.enable = lib.mkDefault false;
    };
  };
}
