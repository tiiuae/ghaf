# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# mkGhafInstaller - Unified Ghaf Installer Builder
#
# Creates bootable ISO installers for Ghaf configurations.
# The installer NixOS system is evaluated once and shared across all targets.
# Per-target ISOs differ only in the embedded Ghaf image, which is injected
# via derivation override instead of a fresh NixOS evaluation.
#
# Usage:
#   let
#     ghafInstaller = ghaf.builders.mkGhafInstaller {
#       inherit self;
#       extraModules = [ ... ];
#     };
#   in ghafInstaller {
#     name = "intel-laptop-debug";
#     imagePath = self.packages.x86_64-linux.intel-laptop-debug;
#   }
#
# First-level parameters (evaluated once, shared across all installers):
#   self         - Flake self reference
#   lib          - Nixpkgs lib (default: self.lib)
#   system       - Target system architecture (default: "x86_64-linux")
#   extraModules - Additional NixOS modules for the installer system
#
# Second-level parameters (per target, no NixOS evaluation):
#   name         - Base name for the installer (e.g., "intel-laptop-debug")
#   imagePath    - Path to the built Ghaf image package
#
# Output:
#   {
#     name    - Full installer name (e.g., "intel-laptop-debug-installer")
#     package - The ISO image derivation
#   }
#
{
  self,
  lib ? self.lib,
  system ? "x86_64-linux",
  extraModules ? [ ],
}:
let
  # Evaluate the base installer NixOS system once. All per-target installers
  # reuse this evaluation via derivation override.
  baseInstallerConfig = lib.nixosSystem {
    specialArgs = {
      inherit lib;
    };
    modules = [
      # Everything not about the boot medium lives in installer-common.nix and is
      # shared with mkGhafNetbootInstaller.nix. Add ISO-specific settings here;
      # add anything else there, or the netboot installer silently loses it.
      (import ./installer-common.nix { inherit self system; })
      (
        { modulesPath, ... }:
        {
          imports = [
            "${toString modulesPath}/installer/cd-dvd/installation-cd-minimal.nix"
          ];

          # ISO-only: these options exist solely because iso-image.nix is imported.
          isoImage = {
            storeContents = [ ];
            contents = [ ];
            squashfsCompression = "zstd -Xcompression-level 3";
          };

          # The image rides along inside the ISO and is mounted at /iso.
          ghaf.installer.imageSource = "/iso/ghaf-image";
        }
      )
    ]
    ++ extraModules;
  };
  baseIsoImage = baseInstallerConfig.config.system.build.isoImage;

  mkGhafInstaller =
    {
      name,
      imagePath,
    }:
    {
      name = "${name}-installer";
      package = baseIsoImage.override {
        contents = baseInstallerConfig.config.isoImage.contents ++ [
          {
            source = "${imagePath}/ghaf-image.raw.zst";
            target = "/ghaf-image/ghaf-image.raw.zst";
          }
          {
            source = "${imagePath}/ghaf-image.bmap";
            target = "/ghaf-image/ghaf-image.bmap";
          }
        ];
      };
    };
in
mkGhafInstaller
