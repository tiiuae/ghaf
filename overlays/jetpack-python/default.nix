# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# Python fixes needed only to build jetpack-nixos' UEFI/EDK2 firmware.
#
# These are deliberately NOT part of `overlays.default`. Both entries reach into
# `pythonPackagesExtensions`, which rewrites *every* Python package in the pkgs
# instance -- and `setuptools-pkg-resources` in particular pins setuptools back
# to 80.x, which breaks any package requiring a newer one (hpack 4.2.0 wants
# >= 82, and takes h2 -> twisted -> s-tui -> system-path down with it).
#
# Only the Jetson targets build the EDK2 firmware, so this overlay is applied by
# the jetpack module (modules/reference/hardware/jetpack/default.nix) instead of
# globally, the same way `overlays.cross-compilation` is applied only for the
# `-from-x86_64` variants.
(_final: prev: {
  pythonPackagesExtensions = prev.pythonPackagesExtensions ++ [
    (import ./pygount)
    (import ./setuptools-pkg-resources)
  ];
})
