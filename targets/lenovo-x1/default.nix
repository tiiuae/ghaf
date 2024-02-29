# Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# Configuration for Lenovo X1 Carbon Gen 11
{
  lib,
  microvm,
  lanzaboote,
  disko,
  ...
}: let
  name = "lenovo-x1-carbon-gen11";
  system = "x86_64-linux";
  targets = import ./everything.nix {inherit lib microvm lanzaboote disko name system;};
in {
  flake.nixosConfigurations =
    builtins.listToAttrs (map (t: lib.nameValuePair t.name t.hostConfiguration) targets);
  flake.packages.${system} =
    builtins.listToAttrs (map (t: lib.nameValuePair t.name t.package) targets);
}
