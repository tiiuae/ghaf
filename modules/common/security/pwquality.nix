# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  config,
  lib,
  ...
}:
let
  cfg = config.ghaf.security.pwquality;
  inherit (lib)
    mkEnableOption
    mkOption
    mkIf
    types
    ;
  creditVal =
    val:
    if val < 0 then
      throw "pwquality value must not be negative: ${toString val}"
    else if val == 0 then
      "0"
    else
      "-" + toString val;
in
{
  _file = ./pwquality.nix;

  options.ghaf.security.pwquality = {
    enable = mkEnableOption "Password quality check.";

    minLength = mkOption {
      description = ''
        Minimum password length.
      '';
      type = types.int;
      default = 8;
    };

    minDigit = mkOption {
      description = ''
        Minimum number of digits required in password.
      '';
      type = types.int;
      default = 1;
    };

    minUppercase = mkOption {
      description = ''
        Minimum number of uppercase letters required in password.
      '';
      type = types.int;
      default = 1;
    };

    minLowercase = mkOption {
      description = ''
        Minimum number of lowercase letters required in password.
      '';
      type = types.int;
      default = 1;
    };

    minSpecialChar = mkOption {
      description = ''
        Minimum number of special letters required in password.
      '';
      type = types.int;
      default = 1;
    };

    rememberOld = mkOption {
      description = ''
        Number of old password to remember to avoid repetetion.
      '';
      type = types.int;
      default = 2;
    };

  };
  config = mkIf cfg.enable {
    environment.etc."security/pwquality.conf".text = ''
      minlen = ${toString config.ghaf.security.pwquality.minLength}
      dcredit = ${creditVal config.ghaf.security.pwquality.minDigit}
      ucredit = ${creditVal config.ghaf.security.pwquality.minUppercase}
      lcredit = ${creditVal config.ghaf.security.pwquality.minLowercase}
      ocredit = ${creditVal config.ghaf.security.pwquality.minSpecialChar}
      remember = ${toString config.ghaf.security.pwquality.rememberOld}
    '';
  };
}
