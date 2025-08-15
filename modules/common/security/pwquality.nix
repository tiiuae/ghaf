# Copyright 2024-2025 TII (SSRC) and the Ghaf contributors
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
in
{
  options.ghaf.security.pwquality = {
    enable = mkEnableOption "Password quality check.";

    min-passwd-len = mkOption {
      description = ''
        Minimum password length.
      '';
      type = types.int;
      default = 8;
    };
  };
  config = mkIf cfg.enable {
    environment.etc."security/pwquality.conf".text = ''
      minlen = ${builtins.toString config.ghaf.security.pwquality.min-passwd-len}
      minclass = 4
      dcredit = -1
      ucredit = -1
      lcredit = -1
      ocredit = -1
      remember = 5
      retry = 3
    '';
  };
}
