# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0

{ buildGoModule, fetchFromGitHub }:
let
  fleet = import ./fleet-package-metadata.nix { inherit fetchFromGitHub; };
in
buildGoModule {
  pname = "fleet-orbit";
  inherit (fleet)
    version
    src
    vendorHash
    goFlags
    ldflags
    ;

  subPackages = [ "orbit/cmd/orbit" ];

  installPhase = ''
    install -Dm755 $GOPATH/bin/orbit $out/bin/orbit
    install -Dm644 orbit/LICENSE $out/share/licenses/fleet-orbit/LICENSE
  '';

  patches = [
    ./patches/osqueryd-path-override.patch
    ./patches/osquery-log-path.patch
    ./patches/write-identifier.patch
    ./patches/orbit-nixos.patch
    ./patches/scripts-nixos.patch
    ./patches/hostname-file.patch
  ];

  meta.mainProgram = "orbit";
}
