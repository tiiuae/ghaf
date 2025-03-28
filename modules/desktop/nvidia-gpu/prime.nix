# Copyright 2025 TII (SSRC) and the Ghaf contributors
# Copyright TLATER
#
# SPDX-License-Identifier: Apache-2.0
# from https://github.com/TLATER/dotfiles
{
  config,
  lib,
  ...
}:
let
  cfg = config.ghaf.graphics.nvidia-setup.prime;
in
{
  options.ghaf.graphics.nvidia-setup.prime = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default =
        config.ghaf.graphics.nvidia-setup.enable && config.ghaf.graphics.nvidia-setup.withIntegratedGPU;
      description = ''
        Whether to configure prime offload.

        This will allow on-demand offloading of rendering tasks to the
        NVIDIA GPU, all other rendering will happen on the GPU
        integrated in the CPU.

        The GPU *should* be turned off whenever it is not in use, so
        this shouldn't cause increased battery drain, but there are
        some reports floating around that this isn't always the case -
        likely especially for older devices. Feel free to turn it off
        if you find this doesn't work properly for you.

      '';
    };
  };

  config = lib.mkIf cfg.enable {
    hardware.nvidia = {
      prime.offload = {
        enable = true;
        enableOffloadCmd = true;
      };

      powerManagement.finegrained = true;
    };
  };
}
