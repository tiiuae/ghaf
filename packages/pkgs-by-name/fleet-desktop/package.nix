# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0

{ buildGoModule, fetchFromGitHub }:
let
  fleet = import ../fleet-orbit/fleet-package-metadata.nix { inherit fetchFromGitHub; };
in
buildGoModule {
  pname = "fleet-desktop";
  inherit (fleet)
    version
    src
    vendorHash
    goFlags
    ldflags
    ;

  env.CGO_ENABLED = "1";
  subPackages = [ "orbit/cmd/desktop" ];

  installPhase = ''
    install -Dm755 $GOPATH/bin/desktop $out/bin/fleet-desktop
    install -Dm644 orbit/LICENSE $out/share/licenses/fleet-desktop/LICENSE
  '';
}
