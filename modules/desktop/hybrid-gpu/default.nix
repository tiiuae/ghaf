# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
#
# SPDX-License-Identifier: Apache-2.0
{ config, lib, ... }:
let
  cfg = config.ghaf.graphics.hybrid-setup;

  environmentVariables = {
    # In our hybrid setup, Nvidia media codecs will be used by default
    LIBVA_DRIVER_NAME = lib.mkForce "nvidia";
    # Required for vainfo functionality
    NVD_GPU = "0";
  };
in
{
  _file = ./default.nix;

  imports = [ ./prime.nix ];

  options.ghaf.graphics.hybrid-setup = {
    enable = lib.mkEnableOption ''
      Hybrid GPU setup that utilizes both Intel and NVIDIA GPU cards
      The Intel GPU will handle rendering tasks, while the Nvidia GPU will be dedicated to media coding.
    '';
  };

  config = lib.mkIf cfg.enable {

    # Enable graphics for Integrated GPU and Nvidia GPU
    ghaf.graphics = {
      intel-setup.enable = true;
      nvidia-setup.enable = true;
    };

    environment.sessionVariables = environmentVariables;
  };
}
