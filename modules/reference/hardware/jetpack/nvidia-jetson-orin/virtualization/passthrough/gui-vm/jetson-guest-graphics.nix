# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# NixOS module that loads the Jetson-compatible NVIDIA graphics stack in a guest VM.
# This file is mostly a 1:1 copy of jetpack-nixos/modules/graphics.nix with options related
# to Xavier, Thor and Jetpack5 removed.
#
{
  config,
  lib,
  pkgs,
  ...
}:
{
  # Allow disabling upstream's NVIDIA modules
  options.hardware.nvidia.enabled = lib.mkOption {
    readOnly = false;
  };

  config = {
    # TEMP: seatd doesn't compile with pVM nixpkgs
    services.seatd.enable = lib.mkForce false;

    boot.kernelModules = [
      "nvgpu"
      "host1x"
      "nvidia-drm"
    ];
    boot.blacklistedKernelModules = [
      "nouveau"
      "nvidia-uvm"
    ];

    boot.extraModprobeConfig = ''
      options nvidia-drm modeset=1
      options nvgpu devfreq_timer="delayed"
    '';
    boot.extraModulePackages = [
      config.boot.kernelPackages.nvidia-oot-modules
    ];

    hardware.nvidia = {
      # The JetPack stack isn't compatible with the upstream NVIDIA modules, which are meant for desktop and
      # datacenter GPUs. We need to disable them so they do not break our Jetson closures.
      # NOTE: Yes, they use "enabled" instead of "enable":
      # https://github.com/NixOS/nixpkgs/blob/ce01daebf8489ba97bd1609d185ea276efdeb121/nixos/modules/hardware/video/nvidia.nix#L27
      enabled = lib.mkForce false;

      # Since some modules use `hardware.nvidia.package` directly, we must ensure it is set to a reasonable package
      # to avoid bloating the Jetson closure with drivers for desktop or datacenter GPUs.
      # As an example, see:
      # https://github.com/NixOS/nixpkgs/blob/ce01daebf8489ba97bd1609d185ea276efdeb121/nixos/modules/services/hardware/nvidia-container-toolkit/default.nix#L173
      package = lib.mkForce config.hardware.graphics.package;
    };

    hardware.graphics.enable = true;
    hardware.graphics.package = pkgs.nvidia-jetpack.l4t-3d-core;
    hardware.graphics.extraPackages =
      let
        # Join and post-process all the other packages providing libs which could be considered part of the driver.
        jetson-graphics-extra-packages = pkgs.symlinkJoin {
          name = "jetson-graphics-extra-packages";
          # Sorted lexicographically to ease insertion of new values.
          paths = lib.attrValues (
            lib.intersectAttrs (lib.genAttrs [
              "l4t-camera"
              "l4t-core"
              "l4t-cuda"
              "l4t-cupva"
              "l4t-dla-compiler" # JP6+
              "l4t-gbm"
              "l4t-multimedia"
              "l4t-nvml" # JP6+
              "l4t-nvsci"
              "l4t-pva"
              "l4t-video-codec-openrm" # JP7+
              "l4t-wayland"
            ] (lib.const null)) pkgs.nvidia-jetpack
          );
          # Exclude all the non-lib/bin stuff.
          # NOTE: Using --force avoids failing when the directory does not exist.
          postBuild = ''
            nixLog "removing argus samples and includes"
            rm -rf "$out/argus"

            nixLog "removing etc"
            rm -rf "$out/etc"

            nixLog "removing include"
            rm -rf "$out/include"

            nixLog "removing lib/python3"
            rm -rf "$out/lib/python3"

            nixLog "removing samples"
            rm -rf "$out/samples"

            nixLog "removing share/doc"
            rm -rf "$out/share/doc"

            nixLog "removing var"
            rm -rf "$out/var"
          '';
        };
      in
      [
        jetson-graphics-extra-packages
      ];

    hardware.firmware = [
      pkgs.nvidia-jetpack.l4t-firmware
    ]
    ++ (
      let
        getDriverDebs =
          prefix:
          (lib.filter (drv: lib.hasPrefix prefix (drv.pname or "")) (
            lib.attrValues pkgs.nvidia-jetpack.driverDebs
          ));
        nvidiaDriverFirmwareDebs = getDriverDebs "nvidia-firmware-";
      in
      nvidiaDriverFirmwareDebs
    );

    environment.etc."egl/egl_external_platform.d".source =
      "${pkgs.addDriverRunpath.driverLink}/share/egl/egl_external_platform.d/";

    services.xserver.drivers = lib.mkForce (
      lib.singleton {
        name = "nvidia";
        modules = [ pkgs.nvidia-jetpack.l4t-3d-core ];
        display = true;
        screenSection = ''
          Option "AllowEmptyInitialConfiguration" "true"
        '';
      }
    );
    services.xserver.videoDrivers = [ "nvidia" ];
    services.xserver.displayManager.lightdm.extraConfig = ''
      logind-check-graphical = false
    '';

    environment.systemPackages =
      (with pkgs.nvidia-jetpack; [
        l4t-tools
        l4t-bootloader-utils
        l4t-cuda
        nvidia-smi
      ])
      ++ (with pkgs.nvidia-jetpack.cudaPackages; [
        cuda_cudart
        cuda_nvrtc
        cuda_nvcc
        libcublas
      ]);
  };
}
