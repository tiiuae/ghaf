# Copyright 2025 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  pkgs,
  ...
}:
{
  ghaf.graphics.nvidia-setup.enable = true;

  microvm.qemu.extraArgs = [
    "-drive"
    "file=${pkgs.OVMF.fd}/FV/OVMF_CODE.fd,if=pflash,unit=0,readonly=true"
    "-drive"
    "file=${pkgs.OVMF.fd}/FV/OVMF_VARS.fd,if=pflash,unit=1,readonly=true"
  ];

  environment.systemPackages = with pkgs; [
    (google-chrome.override {
      # Some of these flags correspond to chrome://flags
      commandLineArgs = [
        "--enable-features=UseOzonePlatform"
        # Correct fractional scaling.
        "--ozone-platform=wayland"
        # Hardware video encoding on Chrome on Linux.
        # See chrome://gpu to verify.
        "--enable-features=VaapiVideoDecoder,VaapiVideoEncoder"
        # Enable H.265 video codec support.
        "--enable-features=WebRtcAllowH265Receive"
        "--force-fieldtrials=WebRTC-Video-H26xPacketBuffer/Enabled"
      ];
    })
  ];
}
