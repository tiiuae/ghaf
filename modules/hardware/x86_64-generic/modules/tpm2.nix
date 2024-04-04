# Copyright 2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.ghaf.hardware.tpm2;
in
  with lib; {
    options.ghaf.hardware.tpm2 = {
      enable = mkEnableOption "TPM2 PKCS#11 interface";
    };

    config = mkIf cfg.enable {
      security.tpm2 = {
        enable = true;
        pkcs11.enable = true;
        abrmd.enable = true;
      };

      environment.systemPackages = mkIf config.ghaf.profiles.debug.enable [
        pkgs.opensc
        pkgs.tpm2-tools
      ];

      assertions = [
        {
          assertion = pkgs.stdenv.isx86_64;
          message = "TPM2 is only supported on x86_64";
        }
      ];
    };
  }
