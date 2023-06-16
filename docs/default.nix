# Copyright 2022-2023 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: CC-BY-SA-4.0
{
  callPackage,
  runCommandNoCC,
  mdbook,
}: let
  footnote = callPackage ./plugins/mdbook-footnote.nix {};
in
  runCommandNoCC "ghaf-doc"
  {
    nativeBuildInputs = [mdbook footnote];
  } ''
    ${mdbook}/bin/mdbook build -d $out ${./.}
  ''
