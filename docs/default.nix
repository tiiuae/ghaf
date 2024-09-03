# Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: CC-BY-SA-4.0
# TODO should this be refactored
{
  lib,
  runCommandLocal,
  nixosOptionsDoc,
  mdbook,
  mdbook-alerts,
  mdbook-footnote,
  revision ? "",
  options ? { },
}:
let
  optionsDocMd =
    (nixosOptionsDoc {
      inherit revision options;
      transformOptions =
        x:
        # TODO this hides the other modules (e.g. microvm.nix)
        # But they are stilled passed as options modules ???
        if lib.strings.hasPrefix "ghaf" x.name then x else x // { visible = false; };
      markdownByDefault = true;
    }).optionsCommonMark;
  combinedSrc = runCommandLocal "ghaf-doc-src" { } ''
    mkdir $out
    cp -r ${./.}/* $out
    chmod +w $out/src/ref_impl/modules_options.md

    # Refer to master branch files in github
    sed 's/\(file:\/\/\)\?\/nix\/store\/[^/]*-source/https:\/\/github.com\/tiiuae\/ghaf\/blob\/main/g' ${optionsDocMd}  >> $out/src/ref_impl/modules_options.md
  '';
in
# TODO Change this, runCommandLocal is not intended for longer running processes
runCommandLocal "ghaf-doc"
  {
    nativeBuildInputs = [
      mdbook
      mdbook-footnote
      mdbook-alerts
    ];
    src = combinedSrc;

    # set the package Meta info
    meta = {
      description = "Ghaf Documentation";
      # TODO should we Only push docs from one Architecture?
      platforms = [
        "x86_64-linux"
        "aarch64-linux"
      ];
    };
  }
  ''
    ${mdbook}/bin/mdbook build -d $out $src
  ''
