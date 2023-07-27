# Copyright 2022-2023 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# Custom format module to be used with nixos-generators,needs path from
# nixos-generators flake input as an argument.
#
{
  imports = [
    ./sdimage.nix
  ];

  formatAttr = "sdImage";
}
