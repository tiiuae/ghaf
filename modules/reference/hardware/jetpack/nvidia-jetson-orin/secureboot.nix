# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0

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
