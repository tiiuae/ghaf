# Copyright 2022-2023 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: CC-BY-SA-4.0
{
  fetchFromGitHub,
  rustPlatform,
}:
rustPlatform.buildRustPackage rec {
  pname = "mdbook-footnote";
  version = "0.1.1";

  src = fetchFromGitHub {
    owner = "daviddrysdale";
    repo = "mdbook-footnote";
    rev = "refs/tags/v${version}";
    sha256 = "sha256-WUMgm1hwsU9BeheLfb8Di0AfvVQ6j92kXxH2SyG3ses=";
  };

  cargoHash = "sha256-Ig+uVCO5oHIkkvFsKiBiUFzjUgH/Pydn4MVJHb2wKGc=";
}
