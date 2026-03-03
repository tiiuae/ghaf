# SPDX-FileCopyrightText: 2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  callPackage,
  python3Packages,
  tpm2PytssCrossPatch,
}:
python3Packages
// {
  tpm2-pytss = callPackage ./package.nix {
    inherit python3Packages;
    inherit tpm2PytssCrossPatch;
  };
}
