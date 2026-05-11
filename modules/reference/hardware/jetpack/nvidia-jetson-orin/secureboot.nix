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
    pkgs.runCommand name
      {
        nativeBuildInputs = [ pkgs.buildPackages.efitools ];
        certPath = cert;
      }
      ''
        if [ ! -s "$certPath" ]; then
          echo "Missing or empty UEFI secure boot certificate: $certPath" >&2
          exit 1
        fi

        ${pkgs.buildPackages.efitools}/bin/cert-to-efi-sig-list "$certPath" "$out"

        if [ "$(wc -c < "$out")" -le 44 ]; then
          echo "Generated ESL ${name} from $certPath is empty" >&2
          exit 1
        fi
      '';

  keysDir = cfg.keysSource;

  requiredCertFiles = [
    (keysDir + "/PK.crt")
    (keysDir + "/KEK.crt")
    (keysDir + "/db.crt")
  ];

  pkEsl = eslFromCert "PK.esl" (keysDir + "/PK.crt");
  kekEsl = eslFromCert "KEK.esl" (keysDir + "/KEK.crt");
  dbEsl = eslFromCert "db.esl" (keysDir + "/db.crt");
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
    assertions = map (certFile: {
      assertion = builtins.pathExists certFile;
      message = "Missing UEFI secure boot certificate `${toString certFile}`. Set `ghaf.hardware.nvidia.orin.secureboot.keysSource` to a directory containing `PK.crt`, `KEK.crt`, and `db.crt`.";
    }) requiredCertFiles;

    hardware.nvidia-jetpack.firmware.uefi.secureBoot = {
      enrollDefaultKeys = true;
      defaultPkEslFile = pkEsl;
      defaultKekEslFile = kekEsl;
      defaultDbEslFile = dbEsl;
    };
  };
}
