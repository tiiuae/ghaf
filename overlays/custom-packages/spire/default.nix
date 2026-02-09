# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{ prev }:
prev.spire.overrideAttrs (_old: rec {
  # version 1.14.2 has build issues (internal 'go' tests fails)
  # Latest nixos-unstable has spire 1.14.4, this overlay can be safely removed after nixpkgs update
  version = "1.14.4";

  src = prev.fetchFromGitHub {
    owner = "spiffe";
    repo = "spire";
    rev = "v${version}";
    hash = "sha256-Ga4fV1a3vlOez12a6lMHoh2CUF9Rkclvjz2FScu6krc=";
  };

  vendorHash = "sha256-Ajoxxpf6oWW6jioMTgeyaIszVhp4j7E2+msE0nhfKpk=";
})
