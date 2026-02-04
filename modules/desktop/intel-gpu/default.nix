# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
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
  _file = ./default.nix;

  options.ghaf.graphics.intel-setup = {
    enable = lib.mkEnableOption "Enable Intel GPU setup";
  };

  config = lib.mkIf cfg.enable {

    hardware.graphics = {
      # hardware.graphics since NixOS 24.11
      enable = true;
      extraPackages = with pkgs; [
        intel-media-driver # For Broadwell (2014) or newer processors, use LIBVA_DRIVER_NAME=iHD
        vpl-gpu-rt # QSV on 11th gen or newer
        intel-compute-runtime
      ];
    };

    environment.sessionVariables = {
      LIBVA_DRIVER_NAME = "iHD";
    }; # Force to use intel-media-driver

  };
}
