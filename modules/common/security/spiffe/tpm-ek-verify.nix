# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# TPM EK Certificate Verification Module
#
# Runs at boot on system VMs with hardware TPM to read the Endorsement Key
# certificate from TPM NV RAM and verify its chain against the combined
# endorsement CA bundle (all.pem).
#
# This is informational/defense-in-depth — the SPIRE server also validates
# the endorsement chain during tpm_devid attestation. This service writes
# status files to /run/tpm/ for operators/monitoring.
#
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.ghaf.security.spiffe.tpmEkVerify;

  tpmEkVerifyApp = pkgs.writeShellApplication {
    name = "tpm-ek-verify";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.tpm2-tools
      pkgs.openssl
    ];
    text = ''
      EK_NV_RSA="0x01C00002"
      EK_NV_ECC="0x01C0000A"
      BUNDLE_PATH="${cfg.endorsementCaBundle}"

      mkdir -p /run/tpm

      # Try to read RSA EK cert first, fall back to ECC
      EK_TYPE=""
      if tpm2_nvread "$EK_NV_RSA" -o /run/tpm/ek-cert.der 2>/dev/null; then
        EK_TYPE="RSA"
      elif tpm2_nvread "$EK_NV_ECC" -o /run/tpm/ek-cert.der 2>/dev/null; then
        EK_TYPE="ECC"
      else
        echo "WARNING: No EK cert found in TPM NV RAM"
        echo "no-ek-cert" > /run/tpm/ek-status
        exit 0
      fi

      echo "$EK_TYPE" > /run/tpm/ek-type

      # Convert DER to PEM
      if ! openssl x509 -inform DER -in /run/tpm/ek-cert.der -out /run/tpm/ek-cert.pem 2>/dev/null; then
        echo "WARNING: Could not convert EK cert from DER to PEM"
        echo "conversion-failed" > /run/tpm/ek-status
        exit 0
      fi

      # Validate chain against all known endorsement CAs
      if openssl verify -partial_chain -CAfile "$BUNDLE_PATH" /run/tpm/ek-cert.pem >/dev/null 2>&1; then
        echo "verified" > /run/tpm/ek-status
        ISSUER=$(openssl x509 -in /run/tpm/ek-cert.pem -noout -issuer 2>/dev/null)
        echo "EK cert ($EK_TYPE) verified: $ISSUER"
      else
        echo "chain-invalid" > /run/tpm/ek-status
        echo "WARNING: EK cert chain validation failed — TPM may not be genuine"
        echo "This is advisory only — SPIRE server will also validate"
      fi
    '';
  };
in
{
  _file = ./tpm-ek-verify.nix;

  options.ghaf.security.spiffe.tpmEkVerify = {
    enable = lib.mkEnableOption "TPM EK certificate verification at boot";

    endorsementCaBundle = lib.mkOption {
      type = lib.types.str;
      default = "";
      description = "Path to combined endorsement CA bundle (all.pem)";
    };
  };

  config = lib.mkIf cfg.enable {
    systemd.services.tpm-ek-verify = {
      description = "Verify TPM EK certificate chain at boot";
      wantedBy = [ "multi-user.target" ];
      after = [
        "local-fs.target"
        "tpm-vendor-detect.service"
      ];
      before = [ "spire-devid-provision.service" ];

      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStart = lib.getExe tpmEkVerifyApp;
      };
    };
  };
}
