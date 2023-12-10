# Copyright 2022-2023 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# Custom format module to be used with nixos-generators,needs path from
# nixos-generators flake input as an argument.
#
{
  lib,
  config,
  ...
}: let
  cgf = config.ghaf.hardware.nvidia.orin;
in {
  imports = [
    ./sdimage.nix
  ];

  # TODO this is default requirement
  # so enabled at the top level of the orin being enabled

  # TODO However, should this be exposed raw like this?
  config = lib.mkIf cfg.enable {
    formatAttr = "sdImage";
  };
}
