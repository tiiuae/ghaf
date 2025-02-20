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
          self.nixosModules.common
          self.nixosModules.host
          self.nixosModules.imx8
          self.nixosModules.reference-personalize
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
              #TODO; we shoudl specify the build platform
              # for both native and cross-compiled cases
              buildPlatform.system = "x86_64-linux";

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

              overlays = [
                inputs.ghafpkgs.overlays.default
                inputs.givc.overlays.default
                inputs.self.overlays.own-pkgs-overlay
                inputs.self.overlays.custom-packages
              ];

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
in
{
  flake = {
    nixosConfigurations = builtins.listToAttrs (
      map (t: lib.nameValuePair t.name t.hostConfiguration) targets
    );
    packages = {
      aarch64-linux = builtins.listToAttrs (map (t: lib.nameValuePair t.name t.package) targets);
    };
  };
}
