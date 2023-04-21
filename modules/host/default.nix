# Copyright 2022-2023 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  self,
  microvm,
  netvm,
  guivm,
}: {lib, ...}: {
  imports = [
    (import ./minimal.nix)

    microvm.nixosModules.host

    ../overlays/custom-packages.nix

    (import ./microvm.nix {inherit self netvm guivm;})
    ./networking.nix
  ];

  networking.hostName = "ghaf-host";
  system.stateVersion = lib.trivial.release;
}
