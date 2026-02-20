# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# TPM Endorsement CA Wiring Module
#
# Resolves vendor names from hardware definition to cert paths from the
# tpm-endorsement-certs package and propagates them to globalConfig.
#
{
  config,
  lib,
  pkgs,
  ...
}:
let
  hwDef = config.ghaf.hardware.definition.tpm;
  # Per-vendor certs (kept for backward compat)
  vendorCerts = map (v: "${pkgs.tpm-endorsement-certs}/vendors/${v}.pem") hwDef.endorsementCaVendors;
  allCerts = vendorCerts ++ hwDef.endorsementCaCerts;
  # Combined bundle with ALL vendor CAs — used by SPIRE server
  allCertsBundle = "${pkgs.tpm-endorsement-certs}/all.pem";
in
{
  _file = ./tpm-endorsement.nix;

  config = {
    # Always set the combined bundle (accepts any genuine TPM)
    ghaf.global-config.spiffe.tpmAttestation.endorsementCaBundle = lib.mkDefault allCertsBundle;

    # Propagate vendor names as advisory (for runtime mismatch warnings)
    ghaf.global-config.spiffe.tpmAttestation.endorsementCaVendors =
      lib.mkDefault hwDef.endorsementCaVendors;

    # Keep per-vendor certs for backward compat
    ghaf.global-config.spiffe.tpmAttestation.endorsementCaCerts = lib.mkIf (allCerts != [ ]) (
      lib.mkDefault allCerts
    );
  };
}
