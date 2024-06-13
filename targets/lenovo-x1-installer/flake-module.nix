# Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# Lenovo X1 Carbon Installer
{
  lib,
  self,
  inputs,
  ...
}: let
  name = "lenovo-x1-carbon";
  system = "x86_64-linux";
  installer = generation: variant: let
    targetName = "${name}-${generation}-${variant}";
    target = self.nixosConfigurations.${targetName};
    hostConfiguration = lib.nixosSystem {
      inherit system;
      modules = [
        ({
          pkgs,
          lib,
          modulesPath,
          ...
        }: let
          diskoInstall = inputs.disko.packages.${system}.disko-install;
          installScript = pkgs.callPackage ../../packages/installer {
            inherit diskoInstall targetName;
            ghafSource = self;

            # Suppose that we have only one "main" disk required
            diskName = with builtins; head (attrNames target.config.ghaf.hardware.definition.disks);
          };

          dependencies =
            [
              target.config.system.build.toplevel
              target.config.system.build.diskoScript
              target.pkgs.stdenv.drvPath
              (target.pkgs.closureInfo {rootPaths = [];}).drvPath
            ]
            ++ builtins.map (i: i.outPath) (builtins.attrValues self.inputs);
          closureInfo = pkgs.closureInfo {rootPaths = dependencies;};
        in {
          imports = [
            "${toString modulesPath}/installer/cd-dvd/installation-cd-minimal.nix"
          ];

          # SSH key to installer for test automation.
          users.users.nixos.openssh.authorizedKeys.keys = lib.mkIf (variant == "debug") (import ../../modules/common/development/authorized_ssh_keys.nix).authorizedKeys;

          systemd.services.wpa_supplicant.wantedBy = lib.mkForce ["multi-user.target"];
          systemd.services.sshd.wantedBy = lib.mkForce ["multi-user.target"];

          environment.etc."install-closure".source = "${closureInfo}/store-paths";

          nix.settings = {
            experimental-features = ["nix-command" "flakes"];
            substituters = lib.mkForce [];
            hashed-mirrors = null;
            connect-timeout = 3;
            flake-registry = pkgs.writeText "flake-registry" ''{"flakes":[],"version":2}'';
          };

          environment.systemPackages = with pkgs; [
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
    name = "${targetName}-installer";
    package = hostConfiguration.config.system.build.isoImage;
  };
  targets = [
    (installer "gen10" "debug")
    (installer "gen11" "debug")
    (installer "gen10" "release")
    (installer "gen11" "release")
  ];
in {
  flake = {
    nixosConfigurations =
      builtins.listToAttrs (map (t: lib.nameValuePair t.name t.hostConfiguration) targets);
    packages.${system} =
      builtins.listToAttrs (map (t: lib.nameValuePair t.name t.package) targets);
  };
}
