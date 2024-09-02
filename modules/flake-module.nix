# Copyright 2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# Modules to be exported from Flake
#
{ inputs, ... }:
{
  imports = [
    ./disko/flake-module.nix
    ./hardware/flake-module.nix
    ./microvm/flake-module.nix
    ./givc/flake-module.nix
  ];

  flake.nixosModules = {
    common.imports = [
      ./common
      {
        ghaf.development.nix-setup.nixpkgs = inputs.nixpkgs;
        nixpkgs.overlays = [ inputs.ghafpkgs.overlays.default ];
      }
    ];
    laptop.imports = [
      ./hardware/definition.nix
      ./hardware/x86_64-generic
      ./reference/hardware/laptop.nix
      ./hardware/common
      { nixpkgs.overlays = [ inputs.ghafpkgs.overlays.default ]; }
    ];
    desktop.imports = [ ./desktop ];
    host.imports = [ ./host ];
    lanzaboote.imports = [ ./lanzaboote ];
    microvm.imports = [ ./microvm ];
    imx8.imports = [ ./reference/hardware/imx8 ];
    jetpack.imports = [ ./reference/hardware/jetpack ];
    jetpack-microvm.imports = [ ./reference/hardware/jetpack-microvm ];
    polarfire.imports = [ ./reference/hardware/polarfire ];
    reference-appvms.imports = [ ./reference/appvms ];
    reference-personalize.imports = [ ./reference/personalize ];
    reference-profiles.imports = [ ./reference/profiles ];
    reference-programs.imports = [ ./reference/programs ];
    reference-services.imports = [ ./reference/services ];
  };
}
