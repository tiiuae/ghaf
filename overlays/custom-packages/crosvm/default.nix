# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# tiiuae fork of crosvm to bring pKVM patches
{ prev }:
let
  version = "0-develop-2026-09-04";
  src = prev.fetchFromGitHub {
    owner = "tiiuae";
    repo = "crosvm";
    rev = "5a799e16db59b3882422203433e0d9a85e22ec7a"; # develop - Aug 20 2026
    fetchSubmodules = true;
    hash = "sha256-IrKOANP4dy4TmmqboGeCMxBEehdhXecte2WbeqWyPac=";
  };
  cargoHash = "sha256-Ald9ftlj7vK2sK3he9U2mhOVL5/uYtaNpvp7JiBkqBk=";
in
prev.crosvm.overrideAttrs (old: {
  inherit version src cargoHash;
  # We need to also pass cargoHash to fetchCargoVendor, otherwise cargoDeps retains
  # the original value from nixpkgs in its scope.
  cargoDeps = prev.rustPlatform.fetchCargoVendor {
    inherit (old) pname;
    inherit src version;
    hash = cargoHash;
  };
  cargoBuildFeatures = (old.cargoBuildFeatures or [ ]) ++ [
    "gdb"
    "pci-hotplug"
    "vtpm"
  ];
  buildInputs = (old.buildInputs or [ ]) ++ [ prev.dbus ];
  patches = [
    ./0001-vhost-user-handle-ACCESS_PLATFORM-for-protected-guest.patch
  ];
})
