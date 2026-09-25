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
    rev = "faae3b634a42ffcc5e893474f914f60a4a67ac0c"; # develop - Sep 16 2026
    fetchSubmodules = true;
    hash = "sha256-mjovUn/8Fbkry1PPiobQ65f58Y1pVTu2fS19MsfwfYA=";
  };
  cargoHash = "sha256-Ald9ftlj7vK2sK3he9U2mhOVL5/uYtaNpvp7JiBkqBk=";
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
    "bpmp"
  ];
})
