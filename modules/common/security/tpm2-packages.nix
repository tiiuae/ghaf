# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# Ghaf-specific TPM2 package overrides.
# Disables abrmd (D-Bus resource manager) since Ghaf accesses TPM directly
# via the kernel resource manager (/dev/tpmrm0).
{
  lib,
  pkgs,
  ...
}:
{
  _file = ./tpm2-packages.nix;

  options.ghaf.security.tpm2 = {
    tools = lib.mkOption {
      type = lib.types.package;
      default = pkgs.tpm2-tools.override {
        abrmdSupport = false;
      };
      defaultText = lib.literalExpression "pkgs.tpm2-tools.override { abrmdSupport = false; }";
      description = "The tpm2-tools package used across Ghaf modules.";
    };

    pkcs11 = lib.mkOption {
      type = lib.types.package;
      default =
        (pkgs.tpm2-pkcs11.override {
          abrmdSupport = false;
        }).overrideAttrs
          (_prevAttrs: {
            configureFlags = [ "--with-fapi=no --enable-fapi=no" ];
          });
      defaultText = lib.literalExpression "pkgs.tpm2-pkcs11 with abrmdSupport=false and FAPI disabled";
      description = "The tpm2-pkcs11 package used across Ghaf modules.";
    };
  };
}
