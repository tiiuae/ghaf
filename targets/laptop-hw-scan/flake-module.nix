# Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# Laptop image to run hardware scan and generate config files
{
  inputs,
  lib,
  self,
  ...
}:
let
  name = "laptop-hw-scan";
  system = "x86_64-linux";
  hw-scan =
    let
      hostConfiguration = lib.nixosSystem {
        inherit system;
        modules = [
          (
            { config, modulesPath, ... }:
            {
              imports = [
                "${toString modulesPath}/installer/cd-dvd/installation-cd-minimal.nix"
                inputs.self.nixosModules.common
                inputs.self.nixosModules.development
                inputs.self.nixosModules.reference-personalize
              ];
              users.users.nixos.openssh.authorizedKeys.keys =
                config.ghaf.reference.personalize.keys.authorizedSshKeys;
              systemd.services.wpa_supplicant.wantedBy = lib.mkForce [ "multi-user.target" ];
              systemd.services.sshd.wantedBy = lib.mkForce [ "multi-user.target" ];
              image.baseName = lib.mkForce "ghaf";
              isoImage.squashfsCompression = "zstd -Xcompression-level 3";
              environment.systemPackages = [ self.packages.x86_64-linux.hardware-scan ];
              networking.networkmanager.enable = true;
              networking.wireless.enable = false;
              boot.kernelParams = [
                # TODO AMD support
                "intel_iommu=on,sm_on"
                "iommu=pt"
              ];

              nixpkgs = {
                hostPlatform.system = "x86_64-linux";

                # Increase the support for different devices by allowing the use
                # of proprietary drivers from the respective vendors
                config.allowUnfree = true;
              };
            }
          )
        ];
      };
    in
    {
      inherit hostConfiguration;
      inherit name;
      package = hostConfiguration.config.system.build.isoImage;
    };
  targets = [ hw-scan ];
in
{
  flake = {
    nixosConfigurations = builtins.listToAttrs (
      map (t: lib.nameValuePair t.name t.hostConfiguration) targets
    );
    packages.${system} = builtins.listToAttrs (map (t: lib.nameValuePair t.name t.package) targets);
  };
}
