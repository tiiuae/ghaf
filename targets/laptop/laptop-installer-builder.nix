# Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#

# Laptop Installer
{
  lib,
  self,
  ...
}:
let
  system = "x86_64-linux";

  mkLaptopInstaller =
    name: imagePath: extraModules:
    let
      hostConfiguration = lib.nixosSystem {
        inherit system;
        modules = [
          (
            { pkgs, modulesPath, ... }:
            {
              imports = [
                "${toString modulesPath}/installer/cd-dvd/installation-cd-minimal.nix"
              ];

              environment.sessionVariables = {
                IMG_PATH = imagePath;
              };

              systemd.services.wpa_supplicant.wantedBy = lib.mkForce [ "multi-user.target" ];
              systemd.services.sshd.wantedBy = lib.mkForce [ "multi-user.target" ];

              isoImage.isoBaseName = lib.mkForce "ghaf";
              networking.hostName = "ghaf-installer";

              environment.systemPackages = [
                self.packages.x86_64-linux.ghaf-installer
                self.packages.x86_64-linux.hardware-scan
              ];

              services.getty = {
                greetingLine = ''<<< Welcome to the Ghaf installer >>>'';
                helpLine = lib.mkAfter ''

                  To run the installer, type
                  `sudo ghaf-installer` and select the installation target.
                '';
              };

              isoImage.squashfsCompression = "zstd -Xcompression-level 3";

              # NOTE: Stop nixos complains about "warning:
              # mdadm: Neither MAILADDR nor PROGRAM has been set. This will cause the `mdmon` service to crash."
              # https://github.com/NixOS/nixpkgs/blob/master/nixos/modules/profiles/installation-device.nix#L112
              boot.swraid.mdadmConf = "PROGRAM ${pkgs.coreutils}/bin/true";
            }
          )
        ] ++ extraModules;
      };
    in
    {
      inherit hostConfiguration;
      name = "${name}-installer";
      package = hostConfiguration.config.system.build.isoImage;
    };

  # Define the installer function
  installer = generation: variant:
    let
      name = "lenovo-x1-${generation}-${variant}";
      imagePath = self.packages.x86_64-linux."${name}" + "/image/disk1.raw.zst";
    in
      mkLaptopInstaller name imagePath [];

  # List of targets
  targets = [
    (installer "gen10" "debug")
    (installer "gen11" "debug")
    (installer "gen12" "debug")
    (installer "gen10" "release")
    (installer "gen11" "release")
    (installer "gen12" "release")
  ];

  # Function to bundle image and flash script
  genPkgWithFlashScript =
    pkg:
    let
      pkgs = import self.inputs.nixpkgs { inherit system; };
    in
    pkgs.linkFarm "ghaf-image" [
      {
        name = "image";
        path = pkg;
      }
      {
        name = "flash-script";
        path = pkgs.callPackage ../../packages/flash { };
      }
    ];
in
{
  flake = {
    nixosConfigurations = builtins.listToAttrs (
      map (t: lib.nameValuePair t.name t.hostConfiguration) targets
    );
    packages.${system} = builtins.listToAttrs (
      map (t: lib.nameValuePair t.name (genPkgWithFlashScript t.package)) targets
    );
  };
}
