# Copyright 2022-2023 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{self}: {
  lib,
  pkgs,
  modulesPath,
  ...
}: {
  imports = [
    # TODO remove this when the minimal config is defined
    # Replace with the baseModules definition
    (modulesPath + "/profiles/minimal.nix")

    ../../overlays/custom-packages.nix

    ./networking.nix
    {
      ghaf = {
        host.networking.enable = true;
        host.networking.netvm.enable = false;
      };
    }
  ];

  /*
  Don't build all modules
  */
  disabledModules = ["profiles/all-hardware.nix"];

  config = {
    networking.hostName = "ghaf-host";
    system.stateVersion = lib.trivial.release;

    ####
    # temp means to reduce the image size
    # TODO remove this when the minimal config is defined
    appstream.enable = false;
    boot = {
      enableContainers = false;
      consoleLogLevel = 4;
      loader = {
        grub.enable = false;
        generic-extlinux-compatible.enable = true;
      };
    };
  };
}
