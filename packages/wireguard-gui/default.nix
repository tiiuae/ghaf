{ wrapGAppsHook, fetchFromGitHub, lib, rustPlatform, pkg-config, wireguard-tools, glib, gtk4, polkit }:
rustPlatform.buildRustPackage rec {
  pname = "wireguard-gui";
  version = "0.1.0";

  src = fetchFromGitHub {
    owner = "tiiuae";
    repo = pname;
    rev = "3f4133ef1f92300db7c5e4a8720af2ab2e80584e";
    sha256 = "sha256-LEOP2wKovsj8NZ7UVX86f+hwmVRYay+rRjOinDKQcD0=";
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

  cargoHash = "sha256-XO/saJfdiawN8CF6oF5HqrvLBllNueFUiE+7A7XWC5M=";
  # cargoHash = "";
}