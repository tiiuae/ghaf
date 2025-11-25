# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# Fix gjs cross-compilation by properly separating native and target dependencies.
# This is based on https://github.com/NixOS/nixpkgs/pull/461666
{ prev }:
prev.gjs.overrideAttrs (
  _final: prevAttrs:
  let
    # When cross-compiling or when doCheck is false, skip GTK tests
    skipGtkTests =
      !prev.stdenv.buildPlatform.canExecute prev.stdenv.hostPlatform || !(prevAttrs.doCheck or true);
  in
  {
    # Enable strict dependencies to prevent mixing native and target packages
    strictDeps = true;

    # Move test dependencies from nativeCheckInputs to checkInputs
    nativeCheckInputs = [ prev.xvfb-run ];

    checkInputs = prev.lib.remove prev.xvfb-run (prevAttrs.nativeCheckInputs or [ ]);

    # Add skip_gtk_tests meson flag
    mesonFlags = (prevAttrs.mesonFlags or [ ]) ++ [
      (prev.lib.mesonBool "skip_gtk_tests" skipGtkTests)
    ];
  }
)
