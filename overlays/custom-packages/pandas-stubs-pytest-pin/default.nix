# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# Backport of https://github.com/NixOS/nixpkgs/pull/545267 -- remove once that
# lands in the nixpkgs we track.
#
# pandas-stubs 3.0.3.260530 cannot be built against pytest 9.1. Its test suite
# passes generators to `@pytest.mark.parametrize`, which pytest 9.1 flags with a
# new PytestRemovedIn10Warning, and the upstream pyproject.toml sets
# `filterwarnings = ["error", ...]`:
#
#   E  pytest.PytestRemovedIn10Warning: Passing a non-Collection iterable to
#      parametrize is deprecated.
#   !!!!!! Interrupted: 8 errors during collection !!!!!!
#
# That happens during collection, so `disabledTests` cannot route around it --
# the eight test modules fail before any test is selected.
#
# Pinning the test run to pytest 9.0 is what nixpkgs does elsewhere for this
# exact fallout (borgbackup, typer, caldav, frictionless and ~9 others already
# use pytest9_0CheckHook). Upstream pandas-stubs has not converted the affected
# generators yet, see pandas-dev/pandas-stubs#1750, and 3.0.3.260530 is still
# their latest release -- so there is no version to bump to instead.
#
# Ghaf hits this because pandas-stubs is a test-time dependency of pdfplumber:
#
#   <target> -> gui-vm -> ghaf-desktop-entries -> falcon-launcher -> alpaca
#            -> python3.14-markitdown -> python3.14-pdfplumber
#            -> python3.14-pandas-stubs (nativeCheckInputs)
_pyFinal: pyPrev: {
  pandas-stubs = pyPrev.pandas-stubs.override {
    pytestCheckHook = pyPrev.pytest9_0CheckHook;
  };
}
