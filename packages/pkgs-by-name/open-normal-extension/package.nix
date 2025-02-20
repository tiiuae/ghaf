# Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  stdenvNoCC,
  pkgs,
  lib,
  makeWrapper,
  ...
}:
stdenvNoCC.mkDerivation {
  name = "open-normal-extension";

  src = ./.;

  nativeBuildInputs = [ makeWrapper ];

  buildInputs = [
    pkgs.coreutils
  ];

  postInstall = ''
    mkdir -p "$out"
    cp -v ./fi.ssrc.open_normal.json ./manifest.json ./open_normal.js ./open_normal.sh "$out"
    chmod a+x "$out/open_normal.sh"

    # Replace $out in json file with actual path and remove comment lines
    # Comments are not allowed in .json, but ghaf automatic checks require them in source files
    substituteInPlace "$out/fi.ssrc.open_normal.json" \
      --replace "\$""{"out"}" "$out" \
      --replace '^\s*\/\/' ""
    # Note that comments are explicitly allowed in browser extension's manifest.json

    # Make sure od is available in PATH for the action script
    wrapProgram "$out/open_normal.sh" --prefix PATH : ${lib.makeBinPath [ pkgs.coreutils ]}
  '';

  meta = with lib; {
    description = "Browser extension for trusted browser to launch normal browser";
    platforms = [
      "x86_64-linux"
      "aarch64-linux"
    ];
  };
}
