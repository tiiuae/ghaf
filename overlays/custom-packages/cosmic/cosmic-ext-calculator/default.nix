# SPDX-FileCopyrightText: 2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
# We fast-forward to 0.2.1 here, as nixpkgs upstream is still on 0.2.0
{ prev }:
let
  src = prev.fetchFromGitHub {
    owner = "cosmic-utils";
    repo = "cosmic-ext-calculator";
    tag = "0.2.1";
    hash = "sha256-t8xuM0B2eh2AbAhDgSOGapTwmmm9eC+wHsqwq4Jn5yU=";
  };
in
prev.cosmic-ext-calculator.overrideAttrs (_oldAttrs: {
  inherit src;
  # Explicitly remove unneeded patch
  patches = [ ];
  cargoDeps = prev.rustPlatform.fetchCargoVendor {
    inherit src;
    hash = "sha256-a4WckNyKXS71dT0uYbO7tUUmD0Dw8vSzrPp29O4aiAk=";
  };
})
