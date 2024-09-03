# Copyright 2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# This overlay customizes tpm2-pkcs11 - see comments for details
#
{ prev }:
prev.tpm2-pkcs11.overrideAttrs (_prevAttrs: {
  configureFlags = [ "--with-fapi=no --enable-fapi=no" ];
})
