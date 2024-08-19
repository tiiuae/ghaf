# Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{ lib, ... }:
{
  options.ghaf.guest.kernel.hardening = {
    enable = lib.mkOption {
      description = "Enable Ghaf Guest hardening feature";
      type = lib.types.bool;
      default = false;
    };

    graphics.enable = lib.mkOption {
      description = "Enable support for Graphics in the Ghaf Guest";
      type = lib.types.bool;
      default = false;
    };
  };
}
