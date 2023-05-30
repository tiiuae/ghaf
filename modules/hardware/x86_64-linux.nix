# Copyright 2022-2023 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{...}: {
  nixpkgs.hostPlatform.system = "x86_64-linux";

  # Add this for x86_64 hosts to be able to more generically support hardware.
  # For example Intel NUC 11's graphics card needs this in order to be able to
  # properly provide acceleration.
  hardware.enableRedistributableFirmware = true;

  boot.loader = {
    efi.canTouchEfiVariables = true;
    systemd-boot.enable = true;
  };
}
