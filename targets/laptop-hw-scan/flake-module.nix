# Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# Laptop image to run hardware scan and generate config files
{ lib, self, ... }:
let
  name = "laptop-hw-scan";
  system = "x86_64-linux";
  hw-scan =
    let
      hostConfiguration = lib.nixosSystem {
        inherit system;
        modules = [
          (
            { modulesPath, ... }:
            {
              imports = [ "${toString modulesPath}/installer/cd-dvd/installation-cd-minimal.nix" ];
              users.users.nixos.openssh.authorizedKeys.keys =
                (import ../../modules/reference/personalize/authorizedSshKeys.nix).authorizedSshKeys;
              systemd.services.wpa_supplicant.wantedBy = lib.mkForce [ "multi-user.target" ];
              systemd.services.sshd.wantedBy = lib.mkForce [ "multi-user.target" ];
              isoImage.isoBaseName = "ghaf";
              isoImage.squashfsCompression = "zstd -Xcompression-level 3";
              environment.systemPackages = [ self.packages.x86_64-linux.hardware-scan ];
              boot.kernelParams = [
                # TODO AMD support
                "intel_iommu=on,sm_on"
                "iommu=pt"
              ];
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
