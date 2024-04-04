# Copyright 2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{lib, ...}:
with lib; {
  options.ghaf.graphics.hardware = {
    networkDevice = mkOption {
      type = types.anything;
      default = {};
      description = ''
        Network device interface for use with graphics stack.
      '';
    };
  };
}
