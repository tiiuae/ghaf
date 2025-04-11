# Copyright 2025 TII (SSRC) and the Ghaf contributors
#
# SPDX-License-Identifier: Apache-2.0
{
  pkgs,
  config,
  lib,
  ...
}:
let
  cfg = config.ghaf.graphics.intel-setup;
in
{
  options.ghaf.graphics.intel-setup = {
    enable = lib.mkEnableOption "Enable Intel GPU setup";
  };

  config = lib.mkIf cfg.enable {

    hardware.graphics = {
      # hardware.graphics since NixOS 24.11
      enable = true;
      extraPackages = with pkgs; [
        intel-media-driver # LIBVA_DRIVER_NAME=iHD
        intel-vaapi-driver # LIBVA_DRIVER_NAME=i965 (older but might work better for Firefox/Chromium)
        libvdpau-va-gl
      ];
    };

    # TODO: to check if i965 is indeed better
    environment.sessionVariables = {
      LIBVA_DRIVER_NAME = "iHD";
    }; # Force intel-media-driver
  };
}
