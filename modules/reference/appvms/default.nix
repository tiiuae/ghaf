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

    # Enable all reference appvms by default when parent enable is set
    ghaf.reference.appvms = {
      business.enable = lib.mkDefault true;
      chromium.enable = lib.mkDefault true;
      comms.enable = lib.mkDefault true;
      flatpak.enable = lib.mkDefault true;
      gala.enable = lib.mkDefault true;
      chrome.enable = lib.mkDefault true;
      zathura.enable = lib.mkDefault true;
    };
  };
}
