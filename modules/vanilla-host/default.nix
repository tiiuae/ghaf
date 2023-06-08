# Copyright 2022-2023 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{ self}: {lib, ...}: {
  imports = [
    (import ./minimal.nix)
    ./networking.nix
  ];
  system.stateVersion = lib.trivial.release;
}
