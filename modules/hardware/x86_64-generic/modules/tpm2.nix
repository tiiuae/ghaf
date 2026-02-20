# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.ghaf.hardware.tpm2;
in
{
  _file = ./tpm2.nix;

  options.ghaf.hardware.tpm2 = {
    enable = lib.mkEnableOption "TPM2 PKCS#11 interface";
  };

  config = lib.mkIf cfg.enable {
    security.tpm2 = {
      enable = true;
      pkcs11.enable = true;
      abrmd.enable = false;
    };

    environment.systemPackages = lib.mkIf config.ghaf.profiles.debug.enable [
      pkgs.opensc
      pkgs.tpm2-tools
    ];

    assertions = [
      {
        assertion = pkgs.stdenv.isx86_64 || pkgs.stdenv.isAarch64;
        message = "TPM2 is only supported on x86_64 and aarch64";
      }
    ];
  };
}
