# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# tiiuae fork of crosvm to bring pKVM patches
#
{
  crosvm,
  fetchFromGitHub,
  rustPlatform,
  dbus,
}:
let
  version = "0-develop-2026-09-16";
  src = fetchFromGitHub {
    owner = "tiiuae";
    repo = "crosvm";
    rev = "86d84c3f95ff1fbbef67858bd58a0220316887dd"; # develop - Oct 6 2026
    fetchSubmodules = true;
    hash = "sha256-HFaqOqYQKTwOjCBLUaBNYBsGEsIHPHcgwIuX8qHV0gE=";
  };
  cargoHash = "sha256-zr7UbDnSkIWbrYIVnV7ukFeVSiMRaDoanCRs4+33kX8=";
in
crosvm.overrideAttrs (prev: {
  inherit version src cargoHash;

  # We need to also pass cargoHash to fetchCargoVendor, otherwise cargoDeps retains
  # the original value from nixpkgs in its scope.
  cargoDeps = rustPlatform.fetchCargoVendor {
    inherit (prev) pname;
    inherit src version;
    hash = cargoHash;
  };
  buildInputs = (prev.buildInputs or [ ]) ++ [ dbus ];
  patches = [
    ./0001-vhost-user-handle-ACCESS_PLATFORM-for-protected-guest.patch
  ];

  cargoBuildFeatures = (prev.cargoBuildFeatures or [ ]) ++ [
    "gdb"
    "pci-hotplug"
    "vtpm"
    "vendor-devices"
  ];
})
