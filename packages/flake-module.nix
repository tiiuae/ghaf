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

      # Generate comprehensive documentation with maximum module coverage
      # This configuration imports key modules to document all options
      # Note: Some modules have dependencies that can conflict, so we use
      # profiles-workstation which includes most common modules
      packages.doc =
        let
          cfg = lib.nixosSystem {
            specialArgs = {
              inherit self inputs;
              inherit (self) lib;
            };
            modules = [
              # profiles-workstation includes: profiles, microvm, common, desktop, development
              self.nixosModules.profiles-workstation

              # Reference implementations (appvms, services, programs)
              self.nixosModules.reference-profiles
              self.nixosModules.reference-appvms

              # Hardware-specific module for documentation
              self.nixosModules.hardware-lenovo-x1-carbon-gen11

              # Partitioning module
              self.nixosModules.disko-debug-partition

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

                # Enable key profiles to trigger all options being documented
                ghaf = {
                  # Core profiles
                  profiles.debug.enable = true;
                  profiles.graphics.enable = true;

                  # Reference implementation profile (enables appvms, services, etc.)
                  reference.profiles.mvp-user-trial.enable = true;

                  # Development features
                  development = {
                    nix-setup.enable = true;
                    debug.tools.enable = true;
                    ssh.daemon.enable = true;
                  };
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
