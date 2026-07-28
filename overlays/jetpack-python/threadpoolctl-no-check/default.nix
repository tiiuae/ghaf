# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# Drop scipy from the EDK2/UEFI build closure.
#
# threadpoolctl is a runtime dependency of joblib, which edk2-pytool-library
# pulls in (jetpack-nixos pkgs/uefi-firmware/pyenv.nix). It needs scipy *only*
# for its own test suite.
#
# Normally none of this matters: stock python packages are substituted from
# cache.nixos.org. But the sibling `setuptools-pkg-resources` extension pins
# setuptools back to 80.x, which changes the derivation hash of every Python
# package in this instance -- so scipy is a cache miss and gets built from
# source. scipy 1.18.0's hypothesis-driven test suite then fails on a numerical
# tolerance (1 failed / 87695 passed):
#
#   TestDistributions.test_support_moments_sample[Normal]
#   Not equal to tolerance rtol=1e-07, atol=2e-09
#    [1]: 0.0 (ACTUAL), 2.0102755453969153e-09 (DESIRED)
#
# Disabling threadpoolctl's checkPhase removes scipy from the closure outright,
# which is cheaper than building scipy with `doCheck = false` (scipy is a long
# build, and nothing here imports it). threadpoolctl itself is a build-time tool
# dependency of the firmware build, not something Ghaf ships.
#
# Revisit if the setuptools pin in `setuptools-pkg-resources` ever goes away --
# at that point scipy is a cache hit again and this override is dead weight.
_pyFinal: pyPrev: {
  threadpoolctl = pyPrev.threadpoolctl.overridePythonAttrs (_: {
    doCheck = false;
  });
}
