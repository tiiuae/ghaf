# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0

{
  pkgs ? import <nixpkgs> { },
}:
let
  version = "1.46.0";

  src = pkgs.fetchFromGitHub {
    owner = "fleetdm";
    repo = "fleet";
    tag = "orbit-v${version}";
    sha256 = "sha256-yQZ7Bfuyz3QUlIDrM2jd2bd4QnG95tkoXllOT9FFDOU=";
  };

  vendorHash = "sha256-uX0LDDcG1KlSAwA2N7y5QNa/rUEm0QezsvMOx6oorL0=";
  commit = "763cb16123ec1fef7fc0926d84825742d37eb8ab";
  date = "2025-08-11T11:03:34Z";

  goFlags = [ "-buildvcs=false" ];
  ldflags = [
    "-s"
    "-w"
    "-X=github.com/fleetdm/fleet/v4/orbit/pkg/build.Version=${version}"
    "-X=github.com/fleetdm/fleet/v4/orbit/pkg/build.Commit=${commit}"
    "-X=github.com/fleetdm/fleet/v4/orbit/pkg/build.Date=${date}"
  ];
in
{
  orbit = pkgs.buildGoModule {
    pname = "fleet-orbit";
    inherit
      version
      src
      vendorHash
      goFlags
      ldflags
      ;

    env.CGO_ENABLED = "1";
    subPackages = [ "orbit/cmd/orbit" ];

    passthru.updateScript = ./update.sh;

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
  };

  fleet-desktop = pkgs.buildGoModule {
    pname = "fleet-desktop";
    inherit
      version
      src
      vendorHash
      goFlags
      ldflags
      ;

    env.CGO_ENABLED = "1";
    subPackages = [ "orbit/cmd/desktop" ];

    passthru.updateScript = ./update.sh;

    installPhase = ''
      install -Dm755 $GOPATH/bin/desktop $out/bin/fleet-desktop
      install -Dm644 orbit/LICENSE $out/share/licenses/fleet-desktop/LICENSE
    '';
  };
}
