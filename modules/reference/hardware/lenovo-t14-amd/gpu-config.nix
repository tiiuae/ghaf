# SPDX-FileCopyrightText: 2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  lib,
  pkgs,
  ...
}:
{
  # Enable UEFI firmware for AMD iGPU passthrough
  microvm.qemu.extraArgs = [
    "-drive"
    "file=${pkgs.OVMF.fd}/FV/OVMF_CODE.fd,if=pflash,unit=0,readonly=true"
    "-drive"
    "file=${pkgs.OVMF.fd}/FV/OVMF_VARS.fd,if=pflash,unit=1,readonly=true"
  ];

  # Use SimpleDRM framebuffer instead of waiting for GPU driver.
  # This will take over the GOP driver provided by the UEFI firmware.
  # see ./GPU_PASSTHROUGH_ISSUES.md for more details
  ghaf.graphics.boot.renderer = lib.mkForce "simpledrm";
}
