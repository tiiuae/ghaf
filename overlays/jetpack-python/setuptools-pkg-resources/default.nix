# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# nixpkgs' default setuptools (82.0.1) dropped pkg_resources upstream.
# jetpack-nixos's pkgs/uefi-firmware/pyenv.nix builds edk2-pytool-extensions'
# python env expecting pkg_resources to be importable (edk2toolext still does
# `import pkg_resources`), so fall back to the last setuptools release that
# still ships it.
#
# Only for python312, the interpreter stuart.nix builds that env with; pinning
# every interpreter breaks packages that require setuptools >= 82 (hpack,
# propcache) in the image's own python3.
_pyFinal: pyPrev:
let
  # Typeshed stubs use package-data path keys that setuptools 80 rejects.
  withCurrentSetuptools = p: p.override { inherit (pyPrev) setuptools; };
in
if pyPrev.pythonOlder "3.13" then
  {
    setuptools = pyPrev.setuptools_80;
    types-psutil = withCurrentSetuptools pyPrev.types-psutil;
    types-python-dateutil = withCurrentSetuptools pyPrev.types-python-dateutil;
    types-setuptools = withCurrentSetuptools pyPrev.types-setuptools;
  }
else
  { }
