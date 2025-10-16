# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  stdenv,
  debug ? false,
  vms ? 0,
  fetchFromGitHub,
  ...
}:
stdenv.mkDerivation {
  name = "memsocket";

  src = fetchFromGitHub {
    owner = "tiiuae";
    repo = "shmsockproxy";
    rev = "2357926b94ed12c050fdbfbfc0f248393a4c9ea1";
    sha256 = "sha256-9KlHuVbe5qvjRUXj7oyJ1X7CLvqj7/OoVGDWRqpIY2s=";
  };

  CFLAGS = "-O2 -DVM_COUNT=" + (toString vms) + (if debug then " -DDEBUG_ON" else "");
  sourceRoot = "source/app";

  installPhase = ''
    mkdir -p $out/bin
    install ./memsocket $out/bin/memsocket
  '';

  meta = {
    description = "memsocket";
    platforms = [
      "x86_64-linux"
      "aarch64-linux"
    ];
  };
}
