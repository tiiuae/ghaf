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

              # Prevent the image from being included in the nix store
              # by explicitly excluding store contents
              isoImage.storeContents = [ ];

              # Include the image file directly in the ISO filesystem (not in /nix/store)
              # This copies the file without creating a runtime dependency
              # Support both disko (disk1.raw.zst) and verity (ghaf-*.raw.zst) images
              # Use reflinks/hardlinks to avoid duplicating large image files
              isoImage.contents =
                let
                  # Create a derivation that finds the .raw.zst file and creates a normalized reference
                  # Using cp --reflink=auto attempts copy-on-write, falling back to hardlink
                  normalizedImage = pkgs.runCommand "normalized-ghaf-image" { } ''
                    mkdir -p $out
                    # Find the .raw.zst file (either disk1.raw.zst or ghaf-*.raw.zst)
                    imageFile=$(find ${imagePath} -maxdepth 1 -name "*.raw.zst" -type f | head -n 1)
                    if [ -z "$imageFile" ]; then
                      echo "Error: No .raw.zst file found in ${imagePath}" >&2
                      exit 1
                    fi
                    # Use reflink if supported (e.g. btrfs), otherwise hardlink to avoid duplication
                    # This saves significant disk space (6-7GB per installer build) compared to cp.
                    cp --reflink=auto "$imageFile" $out/ghaf-image.raw.zst || \
                      ln "$imageFile" $out/ghaf-image.raw.zst
                  '';
                in
                [
                  {
                    source = "${normalizedImage}/ghaf-image.raw.zst";
                    target = "/ghaf-image/ghaf-image.raw.zst";
                  }
                ];

              environment.sessionVariables = {
                IMG_PATH = "/iso/ghaf-image";
              };

              systemd.services.wpa_supplicant.wantedBy = lib.mkForce [ "multi-user.target" ];
              systemd.services.sshd.wantedBy = lib.mkForce [ "multi-user.target" ];
              networking.networkmanager.enable = true;

              image.baseName = lib.mkForce "ghaf";
              networking.hostName = "ghaf-installer";

              environment.systemPackages = [
                self.packages.${system}.ghaf-installer
                self.packages.${system}.hardware-scan
              ];

              services.getty = {
                greetingLine = "<<< Welcome to the Ghaf installer >>>";
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

              boot = {
                kernelPackages = pkgs.linuxPackages_latest;
                # Disable ZFS support - not compatible with latest. only supported on LTS.
                supportedFilesystems.zfs = lib.mkForce false;
              };

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
