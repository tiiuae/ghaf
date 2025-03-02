# Copyright 2025 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  pkgs,
  lib,
  ...
}:
{
  hardware = {
    graphics.extraPackages = [
      pkgs.egl-wayland
      pkgs.mesa
      pkgs.libGL
    ];
    nvidia = {
      modesetting.enable = true;
      powerManagement.enable = false;
      powerManagement.finegrained = false;
      forceFullCompositionPipeline = true;
      open = false;
      nvidiaSettings = true;
      prime = {
        intelBusId = "PCI:0:11:0";
        nvidiaBusId = "PCI:0:12:0";
        offload.enable = lib.mkForce true;
        offload.enableOffloadCmd = lib.mkForce true;
      };
    };
  };

  # Load nvidia driver for Xorg and Wayland
  services.xserver.videoDrivers = [ "nvidia" ];

  microvm.qemu.extraArgs = [
    "-drive"
    "file=${pkgs.OVMF.fd}/FV/OVMF_CODE.fd,if=pflash,unit=0,readonly=true"
    "-drive"
    "file=${pkgs.OVMF.fd}/FV/OVMF_VARS.fd,if=pflash,unit=1,readonly=true"
  ];
}
