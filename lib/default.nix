# SPDX-FileCopyrightText: 2022-2023 TII (SSRC) and the Ghaf contributors
#
# SPDX-License-Identifier: Apache-2.0
{
  lib,
  inputs,
}: let
  inherit (inputs) nixpkgs;
  inherit (inputs) nixos-generators;
in {
  installer = {
    system,
    sshKeys,
    modules ? [],
  }: let
    installerImgCfg = lib.nixosSystem {
      inherit system;
      specialArgs = {inherit lib;};
      modules =
        [
          ../modules/host

          ({
            pkgs,
            lib,
            modulesPath,
            ...
          }: {
            imports = [(modulesPath + "/profiles/all-hardware.nix")];

            environment.systemPackages = [(pkgs.callPackage ../packages/wifi-connector {useNmcli = true;})];

            nixpkgs.hostPlatform.system = system;
            nixpkgs.config.allowUnfree = true;

            hardware.enableAllFirmware = true;

            networking = {
              # wireless is disabled because we use NetworkManager for wireless
              wireless.enable = lib.mkForce false;
              networkmanager.enable = true;
            };

            ghaf = {
              profiles = {
                installer.enable = true;
                debug.enable = true;
              };
              development.ssh.daemon = {
                enable = true;
                authorizedKeys = sshKeys;
              };
            };
          })
        ]
        ++ (import ../modules/module-list.nix)
        ++ modules
        # NOTE: Stick with install-iso as nixos-anywhere requires VARIANT=installer
        # https://nix-community.github.io/nixos-anywhere/howtos/no-os.html#installing-on-a-machine-with-no-operating-system
        ++ [nixos-generators.nixosModules.install-iso];
    };
  in
    installerImgCfg.config.system.build.${installerImgCfg.config.formatAttr};
}
