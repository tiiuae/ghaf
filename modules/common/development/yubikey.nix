# Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{ config, lib, ... }:
let
  cfg = config.ghaf.development.yubikey;
  inherit ((import ./authorized_yubikeys.nix)) authorizedYubikeys;
  inherit (lib)
    mkEnableOption
    mkIf
    concatStrings
    mkForce
    ;
in
{
  options.ghaf.development.yubikey = {
    enable = mkEnableOption "Yubikey test";
  };

  config = mkIf cfg.enable {
    ghaf.services.yubikey.u2fKeys = mkForce (concatStrings authorizedYubikeys);
  };
}
