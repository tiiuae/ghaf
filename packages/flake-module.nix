# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  self,
  inputs,
  ...
}:
{
  imports = [
    inputs.pkgs-by-name-for-flake-parts.flakeModule
    ./own-pkgs-overlay.nix
  ];
  perSystem =
    {
      pkgs,
      lib,
      system,
      ...
    }:
    let
      inherit (pkgs) callPackage;
    in
    {
      #use the pkgs-by-name-for-flake-parts to get the packages
      # exposed to downstream projects
      pkgsDirectory = ./pkgs-by-name;

      # Re-export the updater from the exact GIVC revision pinned by this flake.
      apps.ghaf-ota-update = inputs.givc.apps.${system}.ota-update;

      # Shared image builders live in ghafpkgs; preserve the public flake names.
      packages.ghaf-image-tools = inputs.ghafpkgs.packages.${system}.ghaf-image-tools;
      packages.ghaf-initialize-verity-lvm = inputs.ghafpkgs.packages.${system}.ghaf-initialize-verity-lvm;
      packages.ghaf-wrap-luks-image = inputs.ghafpkgs.packages.${system}.ghaf-wrap-luks-image;
      packages.lvm2-offline = inputs.ghafpkgs.packages.${system}.lvm2-offline;

      # Generate comprehensive documentation with enhanced module coverage
      packages.doc =
        let
          cfg = lib.nixosSystem {
            # Enhanced from intel-laptop-debug with broader module coverage
            specialArgs = {
              inherit inputs;
            };
            modules = [
              # Original proven working base
              self.nixosModules.reference-profiles
              self.nixosModules.disko-debug-partition
              self.nixosModules.hardware-intel-laptop
              self.nixosModules.profiles-workstation

              # Additional modules for comprehensive options coverage
              self.nixosModules.reference-appvms
              self.nixosModules.development

              {
                nixpkgs = {
                  hostPlatform.system = "x86_64-linux";
                  config = {
                    allowUnfree = true;
                    permittedInsecurePackages = [
                      "jitsi-meet-1.0.8792"
                    ];
                  };
                  overlays = [
                    inputs.ghafpkgs.overlays.default
                    inputs.givc.overlays.default
                    self.overlays.default
                  ];
                };

                # Enable profiles for broader options documentation
                ghaf = {
                  profiles.debug.enable = true;
                  reference.profiles.mvp-user-trial.enable = true;
                };
              }
            ];
          };
        in
        callPackage ../docs {
          revision = lib.strings.fileContents ../.version;
          inherit (cfg) options;
          inherit (cfg.pkgs) givc-docs;
        };
    };
}
