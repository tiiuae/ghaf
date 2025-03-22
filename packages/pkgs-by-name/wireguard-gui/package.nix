# Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  wrapGAppsHook,
  fetchFromGitHub,
  rustPlatform,
  pkg-config,
  wireguard-tools,
  glib,
  gtk4,
  polkit,
}:
rustPlatform.buildRustPackage rec {
  pname = "wireguard-gui";
  version = "0.1.0";

  src = fetchFromGitHub {
    owner = "tiiuae";
    repo = pname;
    rev = "6e227e7e244185c65691bb1550fa4d753c32c6df";
    sha256 = "sha256-j06iBT8QMq+DCjU0WHkrCAAVXylu9GWGO2RVdhNn27o=";
    # sha256 = lib.fakeSha256;
  };

  nativeBuildInputs = [
    pkg-config
    wrapGAppsHook
  ];

  buildInputs = [
    wireguard-tools
    glib.dev
    gtk4.dev
    polkit
  ];

  postFixup = ''
    wrapProgram $out/bin/${pname} \
       --set LIBGL_ALWAYS_SOFTWARE true \
       --set G_MESSAGES_DEBUG all 
  '';

  useFetchCargoVendor = true;
  # cargoHash = "sha256-XO/saJfdiawN8CF6oF5HqrvLBllNueFUiE+7A7XWC5M=";
  cargoHash = "sha256-oPtQ/Sg8PRfap4mQcqXmYQjcjli2ySKeeQIARqNFgmQ=";
  # cargoHash = "";
}
