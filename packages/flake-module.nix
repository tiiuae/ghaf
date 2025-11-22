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
      ...
    }:
    let
      inherit (pkgs) callPackage;
    in
    {
      #use the pkgs-by-name-for-flake-parts to get the packages
      # exposed to downstream projects
      pkgsDirectory = ./pkgs-by-name;

      # Generate comprehensive documentation with enhanced module coverage
      packages.doc =
        let
          cfg = lib.nixosSystem {
            # Enhanced from lenovo-x1-carbon-gen11-debug with broader module coverage
            specialArgs = {
              inherit inputs;
            };
            modules = [
              # Original proven working base
              self.nixosModules.reference-profiles
              self.nixosModules.disko-debug-partition
              self.nixosModules.hardware-lenovo-x1-carbon-gen11
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
