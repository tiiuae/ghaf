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

  certFile =
    name:
    if cfg.certificateContents == null then
      keysDir + "/${name}.crt"
    else
      pkgs.writeText "ghaf-secureboot-${name}.crt" cfg.certificateContents.${name};

  requiredCertFiles =
    if cfg.certificateContents == null then
      [
        (keysDir + "/PK.crt")
        (keysDir + "/KEK.crt")
        (keysDir + "/db.crt")
      ]
    else
      [ ];

  pkEsl = eslFromCert "PK.esl" (certFile "PK");
  kekEsl = eslFromCert "KEK.esl" (certFile "KEK");
  dbEsl = eslFromCert "db.esl" (certFile "db");
in
{
  options.ghaf.hardware.nvidia.orin.secureboot = {
    enable = lib.mkEnableOption "UEFI Secure Boot key enrollment for Jetson Orin";

    keysSource = lib.mkOption {
      type = lib.types.path;
      default = ../../../../secureboot/keys;
      description = "Directory containing PK.crt, KEK.crt and db.crt used to generate ESLs.";
    };

    certificateContents = lib.mkOption {
      type = lib.types.nullOr (
        lib.types.submodule {
          options = {
            PK = lib.mkOption { type = lib.types.lines; };
            KEK = lib.mkOption { type = lib.types.lines; };
            db = lib.mkOption { type = lib.types.lines; };
          };
        }
      );
      default = null;
      description = ''
        Public UEFI certificates supplied as text. This imports only public
        material when a development trust directory also contains private keys.
      '';
    };

    signingKeyDir = lib.mkOption {
      type = lib.types.str;
      default = "";
      description = ''
        Path to directory containing db.key and db.crt for signing EFI
        binaries at flash time (on the build host). This is intentionally
        a string (not a path) to avoid copying private keys into the Nix
        store.

        Can be overridden at flash time via the SECURE_BOOT_SIGNING_KEY_DIR
        environment variable.
      '';
    };

    publicTrustDigests = lib.mkOption {
      type = lib.types.attrsOf lib.types.str;
      default = { };
      internal = true;
      description = ''
        SHA-256 digests of the external public trust files embedded during
        evaluation. Flash scripts compare these with the runtime key directory
        before signing or preparing images.
      '';
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
