# SPDX-FileCopyrightText: 2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  lib,
  python3Packages,
  replaceVars,
  stdenv,
  tpm2PytssCrossPatch ? ../../../patches/tpm2-pytss-cross-cpp.patch,
}:
python3Packages.tpm2-pytss.overrideAttrs (old: {
  patches = map (
    p:
    if lib.hasSuffix "cross.patch" (toString p) then
      replaceVars tpm2PytssCrossPatch {
        crossPrefix = stdenv.hostPlatform.config;
      }
    else
      p
  ) (old.patches or [ ]);
})
