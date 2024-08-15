# Copyright 2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
{ config, lib, ... }:
let
  cfg = config.ghaf.profiles.debug;
in
{
  config = lib.mkIf cfg.enable {
    # Enable default accounts and passwords
    ghaf.hardware.nvidia.orin.optee = {
      xtest = true;
      pkcs11-tool = true;
    };
  };
}
