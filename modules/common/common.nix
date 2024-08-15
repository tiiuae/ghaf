# Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# TODO: Refactor even more.
#       This is the old "host/default.nix" file.
{ lib, ... }:
{
  imports = [
    # TODO remove this when the minimal config is defined
    # Replace with the baseModules definition
    # UPDATE 26.07.2023:
    # This line breaks build of GUIVM. No investigations of a
    # root cause are done so far.
    #(modulesPath + "/profiles/minimal.nix")
  ];

  config = {
    system.stateVersion = lib.trivial.release;

    ####
    # temp means to reduce the image size
    # TODO remove this when the minimal config is defined
    appstream.enable = false;
    boot.enableContainers = false;
    documentation.nixos.enable = false;
    ##### Remove to here
  };
}
