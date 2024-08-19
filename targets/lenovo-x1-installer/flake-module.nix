# Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# Lenovo X1 Carbon Installer
{ lib, self, ... }:
let
  name = "lenovo-x1-carbon";
  system = "x86_64-linux";
  installer =
    generation: variant:
    let
      imagePath = self.packages.x86_64-linux."${name}-${generation}-${variant}" + "/disk1.raw.zst";
      hostConfiguration = lib.nixosSystem {
        inherit system;
        modules = [
          (
            { pkgs, modulesPath, ... }:
            let
              installScript = pkgs.callPackage ../../packages/installer { };
            in
            {
              imports = [ "${toString modulesPath}/installer/cd-dvd/installation-cd-minimal.nix" ];

              environment.sessionVariables = {
                IMG_PATH = imagePath;
              };

              # SSH key to installer for test automation.
              users.users.nixos.openssh.authorizedKeys.keys = lib.mkIf (
                variant == "debug"
              ) (import ../../modules/reference/personalize/authorizedSshKeys.nix).authorizedSshKeys;

              systemd.services.wpa_supplicant.wantedBy = lib.mkForce [ "multi-user.target" ];
              systemd.services.sshd.wantedBy = lib.mkForce [ "multi-user.target" ];

              isoImage.isoBaseName = "ghaf";
              networking.hostName = "ghaf-installer";

              environment.systemPackages = [
                installScript
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
        ];
      };
    in
    {
      inherit hostConfiguration;
      name = "${name}-${generation}-${variant}-installer";
      package = hostConfiguration.config.system.build.isoImage;
    };
  targets = [
    (installer "gen10" "debug")
    (installer "gen11" "debug")
    (installer "gen10" "release")
    (installer "gen11" "release")
  ];
in
{
  flake = {
    nixosConfigurations = builtins.listToAttrs (
      map (t: lib.nameValuePair t.name t.hostConfiguration) targets
    );
    packages.${system} = builtins.listToAttrs (map (t: lib.nameValuePair t.name t.package) targets);
  };
}
