# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# tiiuae fork of crosvm to bring pKVM patches
{ prev }:
let
  version = "0-develop-2026-07-23";
  src = prev.fetchFromGitHub {
    owner = "tiiuae";
    repo = "crosvm";
    rev = "0b294d1c87ba3bcd7127df4706c6caf092c516ab"; # develop - Jun 30 2026
    fetchSubmodules = true;
    hash = "sha256-+aM0ifaxwWLtIk9YbCETixZWh/4fFWCcoCtA7XOpE9Y=";
  };
  cargoHash = "sha256-NEmMsCuiEOkanGwT/Oib9yhP+UeT+bCwGI9I3DCWyWU=";
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
