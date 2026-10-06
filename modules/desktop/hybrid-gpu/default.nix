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
    computeLibraries.enable = lib.mkEnableOption "the NVIDIA OpenCL, OptiX and CUDA compiler libraries";
  };

  config = lib.mkIf cfg.enable {

    # Enable graphics for Integrated GPU and Nvidia GPU
    ghaf.graphics = {
      intel-setup.enable = true;
      nvidia-setup.enable = true;
    };

    environment.sessionVariables = environmentVariables;

    # NVIDIA only decodes media here (VA-API over CUDA), so the OpenCL, OptiX and
    # CUDA compiler libraries are dead weight; libcuda itself must stay.
    hardware.nvidia.package = lib.mkIf (!cfg.computeLibraries.enable) (
      lib.mkForce (
        config.boot.kernelPackages.nvidiaPackages.production.overrideAttrs (old: {
          postInstall = toString old.postInstall + ''
            rm -f $out/lib/libnvidia-opencl.* $out/etc/OpenCL/vendors/nvidia.icd \
              $out/lib/libnvidia-nvvm* $out/lib/libnvidia-tileiras.* \
              $out/lib/libnvoptix.* $out/lib/nvoptix.bin $out/lib/libcudadebugger.*
          '';
        })
      )
    );
  };
}
