# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# TPM Vendor Detection Module
#
# Runs at boot on system VMs with hardware TPM to detect the actual
# TPM manufacturer. Writes vendor info to /run/tpm/ for downstream
# services (tpm-ek-verify, monitoring).
#
# If expectedVendors is set and the detected vendor doesn't match,
# a warning is logged (but the service still succeeds — advisory only).
#
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.ghaf.security.spiffe.tpmVendorDetect;

  tpmVendorDetectApp = pkgs.writeShellApplication {
    name = "tpm-vendor-detect";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.gawk
      pkgs.gnused
      pkgs.tpm2-tools
    ];
    text = ''
      mkdir -p /run/tpm

      # Read TPM manufacturer code
      VENDOR_HEX=$(tpm2_getcap properties-fixed 2>/dev/null \
        | grep TPM2_PT_MANUFACTURER -A1 | grep 'raw:' | awk '{print $2}') || true

      if [ -z "$VENDOR_HEX" ]; then
        echo "WARNING: Could not read TPM manufacturer property"
        echo "unknown" > /run/tpm/vendor
        echo "" > /run/tpm/vendor-code
        exit 0
      fi

      # Convert hex to ASCII string (e.g., 0x49465800 -> "IFX")
      # Strip 0x prefix, convert byte pairs to decimal, then to chars via awk
      VENDOR_CODE=$(echo "$VENDOR_HEX" | sed 's/^0x//' | fold -w2 \
        | awk '{val=strtonum("0x"$1); if(val>0) printf "%c",val}')

      # Map vendor codes to TrustedTpm.cab names
      case "$VENDOR_CODE" in
        INTC) VENDOR_NAME="Intel" ;;
        IFX*)  VENDOR_NAME="Infineon" ;;
        AMD*)  VENDOR_NAME="AMD" ;;
        STM*)  VENDOR_NAME="STMicro" ;;
        NTC*)  VENDOR_NAME="Nuvoton" ;;
        QCOM) VENDOR_NAME="QC" ;;
        MSFT) VENDOR_NAME="Microsoft" ;;
        ATML) VENDOR_NAME="Atmel" ;;
        NTZ*)  VENDOR_NAME="NationZ" ;;
        *)    VENDOR_NAME="Unknown" ;;
      esac

      echo "$VENDOR_NAME" > /run/tpm/vendor
      echo "$VENDOR_CODE" > /run/tpm/vendor-code
      echo "TPM vendor: $VENDOR_NAME ($VENDOR_CODE)"

      # Advisory check against expected vendors
      EXPECTED_VENDORS="${lib.concatStringsSep " " cfg.expectedVendors}"
      if [ -n "$EXPECTED_VENDORS" ]; then
        MATCH=0
        for v in $EXPECTED_VENDORS; do
          if [ "$v" = "$VENDOR_NAME" ]; then
            MATCH=1
            break
          fi
        done
        if [ "$MATCH" -eq 0 ]; then
          echo "WARNING: Detected TPM vendor '$VENDOR_NAME' not in expected list: $EXPECTED_VENDORS"
          echo "This is advisory only — attestation will still proceed"
        fi
      fi
    '';
  };
in
{
  _file = ./tpm-vendor-detect.nix;

  options.ghaf.security.spiffe.tpmVendorDetect = {
    enable = lib.mkEnableOption "TPM vendor detection at boot";

    expectedVendors = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = ''
        Expected vendor names (advisory, for warning on mismatch).
        Examples: "Intel", "Infineon", "AMD".
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    systemd.services.tpm-vendor-detect = {
      description = "Detect TPM manufacturer at boot";
      wantedBy = [ "multi-user.target" ];
      after = [ "local-fs.target" ];
      before = [
        "tpm-ek-verify.service"
        "spire-devid-provision.service"
      ];

      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStart = lib.getExe tpmVendorDetectApp;
      };
    };
  };
}
