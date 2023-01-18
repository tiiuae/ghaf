# SPDX-License-Identifier: Apache 2.0
{ ... }:
{
  nix.extraOptions = ''
    experimental-features = nix-command flakes
    keep-outputs          = true
    keep-derivations      = true
    '';
}

