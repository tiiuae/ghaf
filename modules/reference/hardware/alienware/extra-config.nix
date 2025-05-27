# Copyright 2025 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{ pkgs, ... }:
{
  #ghaf.graphics.nvidia-setup.enable = true;
  ghaf.graphics.hybrid-setup = {
    enable = true;
    prime.enable = true;
    # Make sure to use the correct Bus ID values for your system
    prime.nvidiaBusId = "PCI:3:0:0";
    prime.intelBusId = "PCI:0:2:0";
  };

  microvm.qemu.extraArgs = [
    "-drive"
    "file=${pkgs.OVMF.fd}/FV/OVMF_CODE.fd,if=pflash,unit=0,readonly=true"
    "-drive"
    "file=${pkgs.OVMF.fd}/FV/OVMF_VARS.fd,if=pflash,unit=1,readonly=true"
  ];
}
