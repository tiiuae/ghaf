# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# nixpkgs' default setuptools (82.0.1) dropped pkg_resources upstream.
# jetpack-nixos's pkgs/uefi-firmware/pyenv.nix builds edk2-pytool-extensions'
# python env expecting pkg_resources to be importable (edk2toolext still does
# `import pkg_resources`), so fall back to the last setuptools release that
# still ships it.
_pyFinal: pyPrev: {
  setuptools = pyPrev.setuptools_80;
}
