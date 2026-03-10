# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# TPM Endorsement CA Certificates Package
#
# Downloads Microsoft's TrustedTpm.cab (containing root and intermediate CA
# certificates from all approved TPM manufacturers) and produces per-vendor
# PEM bundles. These are used by SPIRE's tpm_devid NodeAttestor to verify
# that DevID keys reside in genuine TPMs.
#
# Output: $out/vendors/{AMD,Intel,Infineon,...}.pem and $out/all.pem
#
{
  lib,
  stdenvNoCC,
  fetchurl,
  cabextract,
  openssl,
}:
stdenvNoCC.mkDerivation {
  pname = "tpm-endorsement-certs";
  version = "2025-08-29"; # Date from cab contents

  src = fetchurl {
    url = "https://go.microsoft.com/fwlink/?linkid=2097925";
    name = "TrustedTpm.cab";
    hash = "sha256-tTmMgD3Ahj12rqccVbkmdiAz6RfD031Vp0Zsso1h2CY=";
  };

  dontUnpack = true;
  nativeBuildInputs = [
    cabextract
    openssl
  ];

  buildPhase = ''
    runHook preBuild

    mkdir extracted
    cabextract -d extracted "$src"
    mkdir -p $out/vendors

    for vendor_dir in extracted/*/; do
      [ -d "$vendor_dir" ] || continue
      vendor_name=$(basename "$vendor_dir")

      # Skip non-vendor directories
      case "$vendor_name" in
        setup.*|*.txt|*.cmd|*.ps1) continue ;;
      esac

      pem_content=""

      # Find all cert files in vendor dir (root + intermediate)
      while IFS= read -r -d "" cert; do
        # Try DER first (most common), fall back to PEM
        converted=$(openssl x509 -inform DER -in "$cert" -outform PEM 2>/dev/null || \
                    openssl x509 -inform PEM -in "$cert" -outform PEM 2>/dev/null || true)
        if [ -n "$converted" ]; then
          pem_content="$pem_content$converted"$'\n'
        else
          echo "WARNING: Could not convert $cert" >&2
        fi
      done < <(find "$vendor_dir" -type f \( -iname "*.cer" -o -iname "*.crt" -o -iname "*.der" \) -print0)

      if [ -n "$pem_content" ]; then
        printf '%s' "$pem_content" > "$out/vendors/$vendor_name.pem"
        cert_count=$(grep -c 'BEGIN CERTIFICATE' "$out/vendors/$vendor_name.pem" || true)
        echo "Wrote $cert_count certs for $vendor_name"
      fi
    done

    # Combined all-vendors PEM
    cat $out/vendors/*.pem > $out/all.pem
    total=$(grep -c 'BEGIN CERTIFICATE' "$out/all.pem" || true)
    echo "Total: $total certs across all vendors"

    runHook postBuild
  '';

  # Everything is done in buildPhase writing directly to $out
  installPhase = "true";

  meta = {
    description = "TPM manufacturer endorsement CA certificates from Microsoft TrustedTpm.cab";
    homepage = "https://learn.microsoft.com/en-us/windows-server/identity/ad-ds/manage/component-updates/tpm-key-attestation";
    license = lib.licenses.unfree; # Microsoft-distributed manufacturer certificates
    platforms = lib.platforms.all;
  };
}
