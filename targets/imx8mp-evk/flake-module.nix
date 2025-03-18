# Copyright 2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# i.MX8M Plus Evaluation Kit
{
  self,
  lib,
  inputs,
  ...
}:
let
  inherit (inputs) nixos-hardware;
  name = "nxp-imx8mp-evk";
  system = "aarch64-linux";
  nxp-imx8mp-evk =
    variant: extraModules:
    let
      hostConfiguration = lib.nixosSystem {
        inherit system;
        specialArgs = {
          inherit lib;
        };
        modules = [
          nixos-hardware.nixosModules.nxp-imx8mp-evk
          self.nixosModules.microvm
          self.nixosModules.imx8
          self.nixosModules.reference-personalize
          self.nixosModules.profiles
          {
            boot = {
              kernelParams = lib.mkForce [ "root=/dev/mmcblk0p2" ];
              loader = {
                grub.enable = false;
                generic-extlinux-compatible.enable = true;
              };
              initrd.systemd.tpm2.enable = false;
            };

            # Disable all the default UI applications
            ghaf = {
              profiles = {
                release.enable = variant == "release";
                debug.enable = variant == "debug";
              };
              development = {
                debug.tools.enable = variant == "debug";
                ssh.daemon.enable = true;
              };
              firewall.kernel-modules.enable = true;
              reference.personalize.keys.enable = variant == "debug";
            };

            nixpkgs = {
              # Increase the support for different devices by allowing the use
              # of proprietary drivers from the respective vendors
              config = {
                allowUnfree = true;
                #jitsi was deemed insecure because of an obsecure potential security
                #vulnerability but it is still used by many people
                permittedInsecurePackages = [
                  "jitsi-meet-1.0.8043"
                ];
              };

              overlays = [ self.overlays.default ];
            };

            hardware.deviceTree.name = lib.mkForce "freescale/imx8mp-evk.dtb";
            hardware.enableAllHardware = lib.mkForce false;
          }
        ] ++ extraModules;
      };
    in
    {
      inherit hostConfiguration;
      name = "${name}-${variant}";
      package = hostConfiguration.config.system.build.sdImage;
    };
  debugModules = [ ];
  releaseModules = [ ];
  targets = [
    (nxp-imx8mp-evk "debug" debugModules)
    (nxp-imx8mp-evk "release" releaseModules)
  ];

  generate-cross-from-x86_64 =
    tgt:
    tgt
    // rec {
      name = tgt.name + "-from-x86_64";
      hostConfiguration = tgt.hostConfiguration.extendModules {
        modules = [ { nixpkgs.buildPlatform.system = "x86_64-linux"; } ]; # buildPlatform to force cross-compilation
      };
      package = hostConfiguration.config.system.build.sdImage;
    };

  crossTargets = map generate-cross-from-x86_64 targets;
in
{
  flake = {
    nixosConfigurations = builtins.listToAttrs (
      map (t: lib.nameValuePair t.name t.hostConfiguration) (targets ++ crossTargets)
    );
    packages = {
      aarch64-linux = builtins.listToAttrs (map (t: lib.nameValuePair t.name t.package) targets);
      x86_64-linux = builtins.listToAttrs (map (t: lib.nameValuePair t.name t.package) crossTargets);
    };
  };
}
