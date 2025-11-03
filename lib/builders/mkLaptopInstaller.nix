# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# Laptop Installer Builder Library
#
# This module provides a reusable function for building laptop installer ISOs
# that can be consumed by both Ghaf internally and downstream projects.
#
# Usage in downstream projects:
#   let mkLaptopInstaller = inputs.ghaf.lib.builders.mkLaptopInstaller inputs.ghaf;
#   in mkLaptopInstaller "my-laptop-installer" "/path/to/image" [...]
{
  self,
  lib ? self.lib,
  system ? "x86_64-linux",
}:
let
  mkLaptopInstaller =
    name: imagePath: extraModules:
    let
      hostConfiguration = lib.nixosSystem {
        specialArgs = {
          inherit lib;
        };
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
              networking.networkmanager.enable = true;
              networking.wireless.enable = false;
              image.baseName = lib.mkForce "ghaf";
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

              # Configure nixpkgs with Ghaf overlays for extended lib support
              nixpkgs = {
                hostPlatform.system = system;
                config = {
                  allowUnfree = true;
                  permittedInsecurePackages = [
                    "jitsi-meet-1.0.8043"
                    "qtwebengine-5.15.19"
                  ];
                };
                overlays = [ self.overlays.default ];
              };
            }
          )
        ]
        ++ extraModules;
      };
    in
    {
      inherit hostConfiguration;
      name = "${name}-installer";
      package = hostConfiguration.config.system.build.isoImage;
    };
in
mkLaptopInstaller
