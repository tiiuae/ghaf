# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
{ config, lib, ... }:
let
  cfg = config.ghaf.profiles.debug;
in
{
  _file = ./debug.nix;

  config = lib.mkIf cfg.enable {
    ghaf.hardware.nvidia.orin.optee = {
      xtest = true;
      pkcs11-tool = true;
    };
  };
}
