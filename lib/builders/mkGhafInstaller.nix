# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# mkGhafInstaller - Unified Ghaf Installer Builder
#
# Creates bootable ISO installers for Ghaf configurations.
# The installer NixOS system is evaluated ONCE (single fixpoint) and shared
# across all targets. Per-target ISOs differ only in the embedded ghaf image,
# which is injected via derivation override: no additional NixOS evaluations.
#
# Usage:
#   let
#     ghafInstaller = ghaf.builders.mkGhafInstaller {
#       inherit self;
#       extraModules = [ ... ];  # NixOS modules for the installer system
#     };
#   in ghafInstaller {
#     name = "lenovo-x1-carbon-gen11-debug";
#     imagePath = self.packages.x86_64-linux.lenovo-x1-carbon-gen11-debug;
#   }
#
# First-level parameters (evaluated once, shared across all installers):
#   self         - Flake self reference
#   lib          - Nixpkgs lib (default: self.lib)
#   system       - Target system architecture (default: "x86_64-linux")
#   extraModules - Additional NixOS modules for the installer system (default: [])
#
# Second-level parameters (per target, no NixOS evaluation):
#   name         - Base name for the installer (e.g., "lenovo-x1-carbon-gen11-debug")
#   imagePath    - Path to the built Ghaf image package
#
# Output:
#   {
#     name    - Full installer name (e.g., "lenovo-x1-carbon-gen11-debug-installer")
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
  # Evaluate the base installer NixOS system ONCE.
  # This is the only lib.nixosSystem call: all per-target installers
  # reuse this evaluation via derivation override.
  baseInstallerConfig = lib.nixosSystem {
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

          isoImage = {
            storeContents = [ ];
            # No ghaf image in base: injected per-target via override
            contents = [ ];
            squashfsCompression = "zstd -Xcompression-level 3";
          };

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

  inherit (baseInstallerConfig) pkgs;

  # The base ISO derivation (no ghaf image embedded).
  # Per-target ISOs override the 'contents' parameter to inject
  # the target's ghaf image without re-evaluating NixOS modules.
  baseIsoImage = baseInstallerConfig.config.system.build.isoImage;

  mkGhafInstaller =
    {
      name,
      imagePath,
    }:
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
    {
      name = "${name}-installer";
      # Override the ISO derivation's contents to inject the target's ghaf image.
      # Append to the base contents (which include /isolinux boot files and other
      # entries added by iso-image.nix) rather than replacing them.
      # This is a pure derivation parameter swap: no NixOS module re-evaluation.
      package = baseIsoImage.override {
        contents = baseInstallerConfig.config.isoImage.contents ++ [
          {
            source = "${normalizedImage}/ghaf-image.raw.zst";
            target = "/ghaf-image/ghaf-image.raw.zst";
          }
        ];
      };
    };
in
mkGhafInstaller
