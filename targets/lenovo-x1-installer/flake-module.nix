# Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# Lenovo X1 Carbon Installer
{
  lib,
  self,
  ...
}: let
  name = "lenovo-x1-carbon-gen11";
  system = "x86_64-linux";
  installer = variant: let
    imagePath = self.packages.x86_64-linux."lenovo-x1-carbon-gen11-${variant}" + "/disk1.raw";
    hostConfiguration = lib.nixosSystem {
      inherit system;
      specialArgs = {inherit lib;};
      modules = [
        ({
          pkgs,
          modulesPath,
          ...
        }: let
          installScript = pkgs.callPackage ../packages/installer {
            inherit imagePath;
          };
        in {
          imports = [
            "${toString modulesPath}/installer/cd-dvd/installation-cd-minimal.nix"
          ];

          systemd.services.wpa_supplicant.wantedBy = lib.mkForce ["multi-user.target"];
          systemd.services.sshd.wantedBy = lib.mkForce ["multi-user.target"];

          isoImage.isoBaseName = "ghaf";

          environment.systemPackages = [
            installScript
          ];

          # NOTE: Stop nixos complains about "warning:
          # mdadm: Neither MAILADDR nor PROGRAM has been set. This will cause the `mdmon` service to crash."
          # https://github.com/NixOS/nixpkgs/blob/master/nixos/modules/profiles/installation-device.nix#L112
          boot.swraid.mdadmConf = "PROGRAM ${pkgs.coreutils}/bin/true";
        })
      ];
    };
  in {
    inherit hostConfiguration;
    name = "${name}-${variant}-installer";
    package = hostConfiguration.config.system.build.isoImage;
  };
  targets = [
    (installer "debug")
    (installer "release")
  ];
in {
  flake = {
    nixosConfigurations =
      builtins.listToAttrs (map (t: lib.nameValuePair t.name t.hostConfiguration) targets);
    packages.${system} =
      builtins.listToAttrs (map (t: lib.nameValuePair t.name t.package) targets);
  };
}
