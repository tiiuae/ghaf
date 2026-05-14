# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  config,
  lib,
  ...
}:
let
  cfg = config.ghaf.services.firmware;
  inherit (lib) mkIf mkEnableOption;
in
{
  _file = ./firmware.nix;

  options.ghaf.services.firmware = {
    enable = mkEnableOption "Placeholder for firmware handling";
  };
  # Previously gated on isX86_64, which made this a no-op on the aarch64
  # Jetson targets — net-vm then shipped without rtl_nic firmware, so the
  # RTL8153 USB-ethernet dongle ran on unpatched ROM firmware and dropped
  # packets intermittently on cold boot (flaky SSH in pre-merge HW tests).
  # USB peripherals passed through to the VMs need their firmware on every
  # arch.
  config = mkIf cfg.enable {
    hardware = {
      enableAllFirmware = true;
    };
  };
}
