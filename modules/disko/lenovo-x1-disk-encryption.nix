# Copyright 2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{lib, ...}:
with lib; {
  options.ghaf.disk.encryption.enable = mkOption {
    description = "Enable Ghaf disk encryption";
    type = types.bool;
    default = false;
  };
}
