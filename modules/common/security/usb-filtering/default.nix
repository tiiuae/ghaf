# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  lib,
  ...
}:
{
  _file = ./default.nix;

  options.ghaf.services.usb-filtering = {
    enable = lib.mkEnableOption "USB device filtering using peripherals VM" // {
      default = false;
    };

    targetVms = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ "periph-vm" ];
      description = "VMs that should have USB device filtering support";
    };
  };
}
