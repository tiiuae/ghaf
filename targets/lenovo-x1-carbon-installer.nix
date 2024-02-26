# Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# Lenovo X1 Carbon Installer
{
  self,
  lib,
}: let
  name = "lenovo-x1-carbon-gen11";
  system = "x86_64-linux";
  installer = variant: let
    image = self.packages.x86_64-linux."lenovo-x1-carbon-gen11-${variant}";
    hostConfiguration = lib.nixosSystem {
      inherit system;
      specialArgs = {inherit lib;};
      modules = [
        ({
          pkgs,
          modulesPath,
          ...
        }: let
          imageScript = pkgs.writeShellScriptBin "ghaf-image" ''
            echo "${image}"
          '';
        in {
          imports = [
            "${toString modulesPath}/installer/cd-dvd/installation-cd-minimal.nix"
          ];

          systemd.services.wpa_supplicant.wantedBy = lib.mkForce ["multi-user.target"];
          systemd.services.sshd.wantedBy = lib.mkForce ["multi-user.target"];

          isoImage.isoBaseName = "ghaf";

          environment.systemPackages = [
            imageScript
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
