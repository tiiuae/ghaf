# Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  flake.nixosModules = {
    graphics.imports = [
      ./labwc.nix
      ./labwc.config.nix
      ./launchers.nix
      ./ewwbar.nix
      ./fonts.nix
      ./login-manager.nix
      ./boot.nix
    ];
  };
}
