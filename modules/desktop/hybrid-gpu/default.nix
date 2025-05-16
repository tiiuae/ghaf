# Copyright 2025 TII (SSRC) and the Ghaf contributors
#
# SPDX-License-Identifier: Apache-2.0
{ config, lib, ... }:
let
  cfg = config.ghaf.graphics.hybrid-setup;

  environmentVariables = {
    # To run an application offloaded to the NVIDIA GPU
    __NV_PRIME_RENDER_OFFLOAD = "1";
    # Use mesa library
    __GLX_VENDOR_LIBRARY_NAME = lib.mkForce "mesa";
    # By default Nvidia media codecs will be used
    LIBVA_DRIVER_NAME = lib.mkForce "nvidia";

  };
in
{
  imports = [ ./prime.nix ];

  options.ghaf.graphics.hybrid-setup = {
    enable = lib.mkEnableOption "Enable Hybrid GPU setup";
  };

  config = lib.mkIf cfg.enable {

    # Enable graphics for Integrated GPU and Nvidia GPU
    ghaf.graphics = {
      intel-setup.enable = true;
      nvidia-setup.enable = true;
    };

    environment.sessionVariables = environmentVariables;
    ghaf.graphics.labwc.extraVariables = environmentVariables;
  };
}
