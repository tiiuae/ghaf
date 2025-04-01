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
  cfg = config.ghaf.graphics.nvidia-setup;
in
{
  imports = [
    ./prime.nix
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
  };

  config = lib.mkIf cfg.enable {

    hardware = {
      graphics.extraPackages = [
        pkgs.egl-wayland
        pkgs.mesa
        pkgs.libGL
        # some vulkan stuff
        #pkgs.libvdpau-va-gl
        pkgs.vulkan-loader
      ];

      nvidia = {
        modesetting.enable = lib.mkDefault true;

        gsp.enable = true;

        # TODO: test enabling these to resume from sleep/suspend states
        powerManagement.enable = false;
        # TODO: this may fix screen tearing but if not needed it can cause more issues
        # than it actually fixes. so leave it to off by default
        forceFullCompositionPipeline = false;
        # TODO: testing the open drivers recommended by nvidia, fails to load the cuda modules
        # and hence fails vaapi support
        open = false; # true;
        nvidiaSettings = true;
        package = config.boot.kernelPackages.nvidiaPackages.beta; # was stable

        dynamicBoost.enable = cfg.enable && cfg.withIntegratedGPU;
      };
    };

    # Load nvidia driver for Xorg and Wayland
    services.xserver.videoDrivers = [ "nvidia" ];

    environment.systemPackages = [ pkgs.vulkan-tools ];

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
        ];
    };

    environment.variables = {
      # Required to run the correct GBM backend for nvidia GPUs on wayland
      GBM_BACKEND = "nvidia-drm";
      # Apparently, without this nouveau may attempt to be used instead
      # (despite it being blacklisted)
      __GLX_VENDOR_LIBRARY_NAME = "nvidia";
      # Hardware cursors are currently broken on wlroots
      # TODO: is this still the case? seems that nixos defaults to 0
      WLR_NO_HARDWARE_CURSORS = lib.mkForce "1";
    };
  };
}
