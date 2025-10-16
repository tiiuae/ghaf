# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
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
  cfg = config.ghaf.graphics.nvidia-setup;

  environmentVariables = {
    # Required to run the correct GBM backend for nvidia GPUs on wayland
    GBM_BACKEND = "nvidia-drm";
    # Apparently, without this nouveau may attempt to be used instead
    # (despite it being blacklisted)
    __GLX_VENDOR_LIBRARY_NAME = "nvidia";
    # Hardware cursors are currently broken on wlroots
    # TODO: is this still the case? seems that nixos defaults to 0
    WLR_NO_HARDWARE_CURSORS = lib.mkForce "1";
  };
in
{
  imports = [
    ./vaapi.nix
  ];

  options.ghaf.graphics.nvidia-setup = {
    enable = lib.mkEnableOption "Enable Nvidia setup";
    withIntegratedGPU = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Whether the computer has a separate integrated GPU.

        This also configures the machine to use the integrated GPU for
        other things like software decoding, so keep this enabled even
        if you separately disable offload rendering.
      '';
    };
    openDrivers = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Whether to use the open source drivers instead of the nvidia
        proprietary drivers, e.g., for Blackwell architectures.
      '';
    };
  };

  config = lib.mkIf cfg.enable {

    hardware = {
      graphics.extraPackages = [
        pkgs.egl-wayland
        # some vulkan stuff
        #pkgs.libvdpau-va-gl
      ];

      nvidia = {
        modesetting.enable = lib.mkDefault true;
        gsp.enable = true;
        open = cfg.openDrivers;
        nvidiaSettings = true;
        package = config.boot.kernelPackages.nvidiaPackages.production; # beta; # was stable

        dynamicBoost.enable = cfg.enable && cfg.withIntegratedGPU;
        # TODO: test enabling these to resume from sleep/suspend states
        powerManagement.enable = false;
        # TODO: this may fix screen tearing but if not needed it can cause more issues
        # than it actually fixes. so leave it to off by default
        forceFullCompositionPipeline = false;
      };
    };

    # Load nvidia driver for Xorg and Wayland
    services.xserver.videoDrivers = [ "nvidia" ];

    boot = {
      # TODO: what exactly does xanmod package bring?
      # https://xanmod.org/
      # many things like clear linux and supposed better nvidia support?
      # https://pq.hosting/en/help/modificirovannoe-jadro-xanmod
      # TODO; seems legit and migth be worth it
      #kernelPackages = lib.mkForce pkgs.linuxKernel.packages.linux_xanmod;

      extraModprobeConfig =
        "options nvidia "
        + lib.concatStringsSep " " [
          # nvidia assume that by default your CPU does not support PAT,
          # but this is effectively never the case in 2023
          "NVreg_UsePageAttributeTable=1"
          # This is sometimes needed for ddc/ci support, see
          # https://www.ddcutil.com/nvidia/
          #
          # Current monitor does not support it, but this is useful for
          # the future
          "NVreg_RegistryDwords=RMUseSwI2c=0x01;RMI2cSpeed=100"

          # The nvidia cuda initialization fails if this is not set in
          # the newer drivers.
          "NVreg_PreserveVideoMemoryAllocations=1"
          # With this setting NVIDIA GPU driver will allow the GPU to go into its lowest power state when no applications are running
          # More details in https://download.nvidia.com/XFree86/Linux-x86_64/435.17/README/dynamicpowermanagement.html
          "NVreg_DynamicPowerManagement=0x02"
        ];
    };

    environment.sessionVariables = environmentVariables;
    ghaf.graphics.labwc.extraVariables = environmentVariables;
  };
}
