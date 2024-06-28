# Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# Configuration for Lenovo X1 Carbon Gen 11
{
  inputs,
  lib,
  self,
  ...
}: let
  name = "lenovo-x1-carbon";
  system = "x86_64-linux";
  targets = import ./everything.nix {inherit self lib inputs name system;};
in {
  flake = {
    nixosConfigurations =
      builtins.listToAttrs (map (t: lib.nameValuePair t.name t.hostConfiguration) targets);
    packages.${system} =
      builtins.listToAttrs (map (t: lib.nameValuePair t.name t.package) targets);
  };
}
