# Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  inputs,
  lib,
  self,
  ...
}:
let
  inherit (inputs) nixos-generators;
  system = "x86_64-linux";
  vm =
    format: variant: withGraphics:
    let
      hostConfiguration = lib.nixosSystem {
        inherit system;
        modules = [
          (builtins.getAttr format nixos-generators.nixosModules)
          self.nixosModules.microvm
          self.nixosModules.profiles
          self.nixosModules.reference-appvms
          self.nixosModules.hardware-x86_64-generic

          {
            ghaf = {
              hardware.x86_64.common.enable = true;

              virtualization = {
                microvm-host = {
                  enable = true;
                  networkSupport = true;
                };

                microvm.guivm.enable = withGraphics;
                # TODO: NetVM enabled, but it does not include anything specific
                #       for this Virtual Machine target
                microvm.netvm.enable = true;
                microvm.adminvm.enable = true;
                microvm.appvm = {
                  enable = true;
                  vms = {
                    zathura = {
                      enable = true;
                      waypipe.enable = withGraphics; # disable waypipe when guivm is not used
                    };
                    gala = {
                      enable = true;
                      waypipe.enable = withGraphics;
                    };
                  };
                };
              };

              reference = {
                appvms.enable = true;
              };

              givc = {
                enable = withGraphics;
                debug = true;
              };

              host.networking.enable = true;

              # Enable all the default UI applications
              profiles = {
                graphics = {
                  enable = withGraphics;
                };
                release.enable = variant == "release";
                debug.enable = lib.hasPrefix "debug" variant;
              };
            };

            nixpkgs = {
              hostPlatform.system = "x86_64-linux";

              # Increase the support for different devices by allowing the use
              # of proprietary drivers from the respective vendors
              config = {
                allowUnfree = true;
                #jitsi was deemed insecure because of an obsecure potential security
                #vulnerability but it is still used by many people
                permittedInsecurePackages = [
                  "jitsi-meet-1.0.8043"
                  "qtwebengine-5.15.19"
                ];
              };

              overlays = [ self.overlays.default ];
            };

            virtualisation = lib.optionalAttrs (format == "vm") {
              graphics = withGraphics;
              useNixStoreImage = true;
              writableStore = true;
              cores = 4;
              memorySize = 8 * 1024;
              forwardPorts = [
                {
                  from = "host";
                  host.port = 8022;
                  guest.port = 22;
                }
              ];
            };
          }
        ];
      };
    in
    {
      inherit hostConfiguration;
      name = "${format}-${variant}";
      package = hostConfiguration.config.system.build.${hostConfiguration.config.formatAttr};
    };
  targets = [
    (vm "vm" "debug" true)
    (vm "vm" "debug-nogui" false)
    (vm "vm" "release" true)
    (vm "vmware" "debug" true)
  ];
in
{
  flake = {
    nixosConfigurations = builtins.listToAttrs (
      map (t: lib.nameValuePair t.name t.hostConfiguration) targets
    );
    packages = {
      x86_64-linux = builtins.listToAttrs (map (t: lib.nameValuePair t.name t.package) targets);
    };
  };
}
