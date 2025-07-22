# Copyright 2025 TII (SSRC) and the Ghaf contributors
# Copyright TLATER
#
# SPDX-License-Identifier: Apache-2.0
# derived from https://github.com/TLATER/dotfiles
{
  pkgs,
  config,
  lib,
  ...
}:
let
  cfg = config.ghaf.graphics.nvidia-setup.vaapi;
  environmentVariables = {
    NVD_BACKEND = "direct";
    LIBVA_DRIVER_NAME = "nvidia";
  }
  // lib.optionalAttrs (cfg.maxInstances != null) { NVD_MAX_INSTANCES = toString cfg.maxInstances; };
in
{
  options.ghaf.graphics.nvidia-setup.vaapi = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default =
        config.ghaf.graphics.nvidia-setup.enable && !config.ghaf.graphics.nvidia-setup.withIntegratedGPU;
      description = ''
        Whether to enable the NVIDIA vaapi driver.

        This allows using the NVIDIA GPU for decoding video streams
        instead of using software decoding on the CPU.

        This particularly makes sense for desktop computers without an
        iGPU, as on those software en/decoding will take a lot of
        processing power while the NVIDIA GPU's encoding capacity
        isn't doing anything, so this option is enabled by default
        there.

        However, on machines with an iGPU, the dGPU's en/decoding
        capabilities are often more limited than those of the iGPU,
        and require more power, so this is disabled there by default -
        it may still make sense from time to time, so feel free to
        experiment.

      '';
    };

    maxInstances = lib.mkOption {
      type = lib.types.nullOr lib.types.int;
      default = null;
      description = ''
        The maximum number of concurrent instances of the driver.

        Sometimes useful for graphics cards with little VRAM.
      '';
    };
  };

  # See https://github.com/elFarto/nvidia-vaapi-driver#configuration
  config = lib.mkIf cfg.enable {
    environment = {
      systemPackages = [ pkgs.libva-utils ];
      sessionVariables = environmentVariables;
    };

    ghaf.graphics.labwc.extraVariables = environmentVariables;

    hardware.graphics.extraPackages = [
      pkgs.nvidia-vaapi-driver
    ];
  };
}
