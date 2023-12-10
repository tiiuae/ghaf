# Copyright 2022-2023 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  lib,
  self,
  inputs,
  ...
}: {
  # TODO include the cross-compilation for the relevant targets
  # The cross-compilation should only be done if the target is a xcompile target, not a local target
  # so a -from-x86
  perSystem = {system, ...}: {
    # create a custom instance of nixpkgs with all our overlays and custom config
    # and make it available to all perSystem functions
    _module.args.pkgs = import inputs.nixpkgs {
      inherit system;
      overlays = import ../overlays;
      config = {
        allowUnfree = true;
      };
      specialArgs = {
        inherit self inputs lib system;
      };
    };
  };
}
