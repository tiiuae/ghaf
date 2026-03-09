# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# UEFI Secure Boot for Jetson Orin
#
# Enrolls PK/KEK/db keys into the firmware via a DTB overlay.
# EFI binaries are signed at flash time by partition-template-verity.nix
# using the db private key. OTA update images should be pre-signed by
# the update server before distribution.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.ghaf.hardware.nvidia.orin.secureboot;

  eslFromCert =
    name: cert:
    pkgs.runCommand name { nativeBuildInputs = [ pkgs.buildPackages.efitools ]; } ''
      ${pkgs.buildPackages.efitools}/bin/cert-to-efi-sig-list ${cert} $out
    '';

  keysDir = cfg.keysSource;

  pkEsl = eslFromCert "PK.esl" "${keysDir}/PK.crt";
  kekEsl = eslFromCert "KEK.esl" "${keysDir}/KEK.crt";
  dbEsl = eslFromCert "db.esl" "${keysDir}/db.crt";
in
{
  options.ghaf.hardware.nvidia.orin.secureboot = {
    enable = lib.mkEnableOption "UEFI Secure Boot key enrollment for Jetson Orin";

    keysSource = lib.mkOption {
      type = lib.types.path;
      default = ../../../../secureboot/keys;
      description = "Directory containing PK.crt, KEK.crt and db.crt used to generate ESLs.";
    };

    signingKeyDir = lib.mkOption {
      type = lib.types.str;
      default = toString ../../../../secureboot/dev-keys;
      description = ''
        Path to directory containing db.key and db.crt for signing EFI
        binaries at flash time (on the build host). This is intentionally
        a string (not a path) to avoid copying private keys into the Nix
        store.

        Can be overridden at flash time via the SECURE_BOOT_SIGNING_KEY_DIR
        environment variable.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    hardware.nvidia-jetpack.firmware.uefi.secureBoot = {
      enrollDefaultKeys = true;
      defaultPkEslFile = pkEsl;
      defaultKekEslFile = kekEsl;
      defaultDbEslFile = dbEsl;
    };
  };
}
