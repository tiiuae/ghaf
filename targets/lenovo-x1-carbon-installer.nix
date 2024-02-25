# Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# Lenovo X1 Carbon Installer
{lib}: let
  name = "lenovo-x1-carbon-gen11";
  system = "x86_64-linux";
  installer = variant: let
    hostConfiguration = lib.nixosSystem {
      inherit system;
      specialArgs = {inherit lib;};
      modules = [
        ({modulesPath, ...}: {
          isoImage.isoBaseName = "ghaf";
          imports = [
            "${toString modulesPath}/installer/cd-dvd/installation-cd-minimal.nix"
          ];
        })
      ];
    };
  in {
    inherit hostConfiguration;
    name = "${name}-${variant}";
    package = hostConfiguration.config.system.build.isoImage;
  };
  lenovo-debug = installer "debug";
in {
  flake.packages = {
    ${system}.lenovo-x1-carbon-gen11-debug-installer = lenovo-debug.package;
  };
}
