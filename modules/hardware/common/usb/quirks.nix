# Copyright 2022-2025 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  config,
  lib,
  ...
}:
let
  cfg = config.ghaf.hardware.usb.quirks;
  inherit (lib)
    mkEnableOption
    mkIf
    ;
  # https://github.com/eihqnh/.nixconfig/blob/a685389652c3df60b1ece49125f3e2db993aeebf/common.nix#L102
  # https://docs.redhat.com/en/documentation/red_hat_enterprise_linux/7/html/7.7_release_notes/kernel_parameters_changes
  quirks = [
    "2357:0601:k" # TP-Link’s USB 3.0 Ethernet adapters (AX88179 chipset)
    "0bda:8153:k" # Realtek Semiconductor Corp. RTL8153 Gigabit Ethernet Adapter
  ];

in
{
  options.ghaf.hardware.usb.quirks = {
    enable = mkEnableOption "quirks for USB devices";
  };

  config = mkIf cfg.enable {

    boot.kernelParams = [
      "usbcore.quirks=${lib.concatStringsSep "," quirks}"
    ];

  };
}
