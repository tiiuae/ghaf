# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  config,
  lib,
  ...
}:
let
  cfg = config.ghaf.host.secureboot;
  inherit (cfg) keysDir;
  keysInEtc = lib.hasPrefix "/etc/" keysDir;
  keysEtcPrefix = lib.removePrefix "/etc/" keysDir;

in
{
  options.ghaf.host.secureboot = {
    enable = lib.mkEnableOption "Secure Boot support";

    keysDir = lib.mkOption {
      type = lib.types.str;
      default = "/etc/ghaf/secureboot/keys";
      description = "Path to the directory containing Secure Boot public keys.";
    };

    keysSource = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = ./keys;
      description = "Source directory for Secure Boot public keys; set to null to skip installing keys.";
    };

  };

  config = lib.mkIf cfg.enable {
    boot.loader.efi.canTouchEfiVariables = lib.mkDefault true;

    environment.etc = lib.mkIf (cfg.keysSource != null && keysInEtc) {
      "${keysEtcPrefix}/PK.auth".source = "${cfg.keysSource}/PK.auth";
      "${keysEtcPrefix}/KEK.auth".source = "${cfg.keysSource}/KEK.auth";
      "${keysEtcPrefix}/KEK.crt".source = "${cfg.keysSource}/KEK.crt";
      "${keysEtcPrefix}/db.auth".source = "${cfg.keysSource}/db.auth";
      "${keysEtcPrefix}/db.crt".source = "${cfg.keysSource}/db.crt";
      "${keysEtcPrefix}/README.md".source = "${cfg.keysSource}/README.md";
    };
  };
}
