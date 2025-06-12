# Copyright 2025 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  buildNpmPackage,
  lib,
  nixosOptionsDoc,
  runCommandLocal,
  pkg-config,
  nodejs,
  vips,
  revision ? "",
  options ? { },
  ...
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
    }).optionsCommonMark;
  combinedSrc = runCommandLocal "ghaf-doc-src" { } ''
    mkdir $out
    cp -r ${./.}/* $out
    chmod +w $out/src/content/docs/ghaf/dev/library/modules_options.mdx

    # Refer to master branch files in github
    sed 's/\(file:\/\/\)\?\/nix\/store\/[^/]*-source/https:\/\/github.com\/tiiuae\/ghaf\/blob\/main/g' ${optionsDocMd}  >> $out/src/content/docs/ghaf/dev/library/modules_options.mdx
  '';
in
buildNpmPackage (_finalAttrs: {
  pname = "ghaf-docs";
  version = "0.1.0";
  src = combinedSrc;
  inherit nodejs;

  buildInputs = [
    vips
  ];

  nativeBuildInputs = [
    pkg-config
  ];
  installPhase = ''
    runHook preInstall
    cp -pr --reflink=auto dist $out/
    runHook postInstall
  '';

  npmDepsHash = "sha256-ckKaqnh2zAe34Hi+fpmf2NqoIB8KyEVMrvv3jdnkp4U=";

})
