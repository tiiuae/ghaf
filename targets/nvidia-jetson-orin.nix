# Copyright 2022-2023 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  self,
  jetpack-nixos,
  microvm,
}: rec {
  system = "aarch64-linux";
  modules = [
    (import ../modules/host {
      inherit self microvm system;
    })

    jetpack-nixos.nixosModules.default
    ../modules/hardware/nvidia-jetson-orin.nix

    ../modules/graphics/weston.nix

    #### on-host development supporting modules ####
    # drop/replace modules below this line for any real use
    ../modules/development/authentication.nix
    ../modules/development/nix.nix
    ../modules/development/packages.nix
    ../modules/development/ssh.nix
  ];
}
