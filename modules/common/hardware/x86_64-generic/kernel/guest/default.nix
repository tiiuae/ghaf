# Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{lib, ...}:
with lib; {
  options.ghaf.guest.kernel.hardening.enable = mkOption {
    description = "Enable Ghaf Guest hardening feature";
    type = types.bool;
    default = false;
  };
  options.ghaf.guest.kernel.hardening.graphics.enable = mkOption {
    description = "Enable support for Graphics in the Ghaf Guest";
    type = types.bool;
    default = false;
  };
}
