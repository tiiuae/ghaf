# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.ghaf.virtualization.storagevm-encryption;
  inherit (lib)
    mkIf
    mkEnableOption
    ;
in
{
  _file = ./storagevm-encryption.nix;

  options.ghaf.virtualization.storagevm-encryption = {
    enable = mkEnableOption "Encryption of the VM storage area for all VMs";
  };

  config = mkIf cfg.enable {
    assertions = [
      {
        assertion = pkgs.stdenv.isx86_64;
        message = "Storage VM encryption is currently only supported for x86 platforms";
      }
    ];
  };
}
