# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  buildNpmPackage,
  lib,
  nixosOptionsDoc,
  runCommandLocal,
  nodejs,
  revision ? "",
  options ? { },
  givc-docs,
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

  combinedSrc =
    runCommandLocal "ghaf-doc-src"
      {
        nativeBuildInputs = [
          givc-docs
        ];
      }
      ''
        mkdir $out
        cp -r ${./.}/* $out
        chmod +w $out/src/content/docs/ghaf/dev/library/modules_options.mdx

        # Refer to master branch files in github
        sed 's/\(file:\/\/\)\?\/nix\/store\/[^/]*-source/https:\/\/github.com\/tiiuae\/ghaf\/blob\/main/g' ${optionsDocMd}  >> $out/src/content/docs/ghaf/dev/library/modules_options.mdx

        # Copy givc API documentation and remove nix store paths
        chmod -R +w $out/src/content/docs/givc
        SRC_DIR="${givc-docs}/api/"
        DEST_DIR="$out/src/content/docs/givc/api/"
        find "$SRC_DIR" -type f | while read -r source_file; do
          dest_file="''${DEST_DIR}''${source_file#$SRC_DIR}"
          mkdir -p "$(dirname "$dest_file")"
          sed "s#nix/store/[a-z0-9-]\+-source/##g" "$source_file" > "$dest_file"
        done
      '';
in
buildNpmPackage (_finalAttrs: {
  pname = "ghaf-docs";
  version = "0.1.0";
  src = combinedSrc;
  inherit nodejs;

  # Note: Sharp is no longer used since we configured astro with passthroughImageService
  # This avoids native dependency issues in Nix sandbox builds

  installPhase = ''
    runHook preInstall
    cp -pr --reflink=auto dist $out/
    runHook postInstall
  '';

  npmDepsHash = "sha256-lK3itnX31kkDGaqhZWECoplo4KlWdAUoWFAwuDSTYvk=";

})
