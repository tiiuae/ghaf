# Copyright 2022-2023 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: CC-BY-SA-4.0
{
  pkgs,
  lib,
  callPackage,
  runCommandLocal,
  nixosOptionsDoc,
  mdbook,
  revision ? "",
  options ? {},
}: let
  optionsDocMd =
    (nixosOptionsDoc {
      inherit revision options;
      transformOptions = x:
        if lib.strings.hasPrefix "ghaf" x.name
        then x
        else x // {visible = false;};
      markdownByDefault = true;
    })
    .optionsCommonMark;
  combinedSrc = runCommandLocal "ghaf-doc-src" {} ''
    mkdir $out
    cp -r ${./.}/* $out
    chmod +w $out/src/ref_impl/modules_options.md

    # Refer to master branch files in github
    sed 's/\(file:\/\/\)\?\/nix\/store\/[^/]*-source/https:\/\/github.com\/tiiuae\/ghaf\/blob\/main/g' ${optionsDocMd}  >> $out/src/ref_impl/modules_options.md
  '';
in
  runCommandLocal "ghaf-doc"
  {
    nativeBuildInputs = let
      footnote = callPackage ./plugins/mdbook-footnote.nix {};
    in [mdbook footnote];
    src = combinedSrc;
  } ''
    ${mdbook}/bin/mdbook build -d $out $src
  ''
