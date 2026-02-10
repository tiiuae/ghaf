# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# Generic x86_64 computer -target
#
# This is a minimal target that runs GUI on the HOST with netvm for networking.
# It uses an inline netvmBase instead of the full laptop-x86 profile.
{
  inputs,
  lib,
  self,
  ...
}:
let
  inherit (inputs) nixos-generators;
  name = "generic-x86_64";
  system = "x86_64-linux";
  generic-x86 =
    variant: extraModules:
    let
      netvmExtraModules = [
        {
          microvm.devices = [
            {
              bus = "pci";
              path = "0000:00:14.3";
            }
          ];

          # For WLAN firmwares including the unfree ones
          hardware.enableAllFirmware = true;

          networking.wireless = {
            enable = true;

            # networks."SSID_OF_NETWORK".psk = "WPA_PASSWORD";
          };
        }
      ];
      hostConfiguration = lib.nixosSystem {
        specialArgs = {
          inherit (self) lib;
          inherit inputs; # Required for microvm modules
        };
        modules = [
          nixos-generators.nixosModules.raw-efi
          self.nixosModules.microvm
          self.nixosModules.hardware-x86_64-generic
          self.nixosModules.profiles
          self.nixosModules.reference-host-demo-apps
          self.nixosModules.reference-programs

          (
            {
              lib,
              config,
              pkgs,
              modulesPath,
              ...
            }:
            let
              # Get globalConfig from host configuration
              globalConfig = config.ghaf.global-config;

              # Create inline netvmBase (following laptop-x86 pattern)
              netvmBase = lib.nixosSystem {
                modules = [
                  inputs.microvm.nixosModules.microvm
                  inputs.self.nixosModules.netvm-base
                  # Import nixpkgs config for overlays
                  {
                    nixpkgs = {
                      hostPlatform.system = "x86_64-linux";
                      inherit (config.nixpkgs) overlays;
                      inherit (config.nixpkgs) config;
                    };
                  }
                ];
                specialArgs = lib.ghaf.vm.mkSpecialArgs {
                  inherit lib inputs globalConfig;
                  hostConfig = lib.ghaf.vm.mkHostConfig {
                    inherit config;
                    vmName = "net-vm";
                  };
                  # Note: netvm.wifi now controlled via globalConfig.features.wifi
                };
              };
            in
            {
              # https://github.com/nix-community/nixos-generators/blob/master/formats/raw-efi.nix#L24-L29
              system.build.raw = lib.mkOverride 98 (
                import "${toString modulesPath}/../lib/make-disk-image.nix" {
                  inherit lib config pkgs;
                  partitionTableType = "efi";
                  inherit (config.virtualisation) diskSize;
                  format = "raw";
                  postVM = "${pkgs.zstd}/bin/zstd --compress --rm $out/nixos.img";
                }
              );

              # Wire up netvm using inline netvmBase
              ghaf.virtualization.microvm.netvm.evaluatedConfig = netvmBase.extendModules {
                modules = config.ghaf.hardware.definition.netvm.extraModules or [ ];
              };
            }
          )

          {
            ghaf = {
              hardware.x86_64.common.enable = true;

              # Hardware passthrough for netvm (WiFi device)
              hardware.definition.netvm.extraModules = netvmExtraModules;

              virtualization = {
                microvm-host = {
                  enable = true;
                  networkSupport = true;
                };

                microvm.netvm.enable = true;
              };

              host.networking.enable = true;

              # Enable all the default UI applications
              profiles = {
                graphics.enable = true;
                release.enable = variant == "release";
                debug.enable = variant == "debug";
              };
              reference.programs.windows-launcher.enable = true;
              reference.host-demo-apps.demo-apps.enableDemoApplications = true;
            };

            nixpkgs = {
              hostPlatform.system = system;

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

            #TODO: how to handle the majority of laptops that need a little
            # something extra?
            # SEE: https://github.com/NixOS/nixos-hardware/blob/master/flake.nix
            # nixos-hardware.nixosModules.lenovo-thinkpad-x1-10th-gen

            boot.kernelParams = [
              "intel_iommu=on,igx_off,sm_on"
              "iommu=pt"

              # TODO: Change per your device
              # Passthrough Intel WiFi card
              "vfio-pci.ids=8086:a0f0"
            ];
          }
        ]
        ++ extraModules;
      };
    in
    {
      inherit hostConfiguration;
      name = "${name}-${variant}";
      package = hostConfiguration.config.system.build.${hostConfiguration.config.formatAttr};
    };
  debugModules = [ { ghaf.development.usb-serial.enable = true; } ];
  targets = [
    (generic-x86 "debug" debugModules)
    (generic-x86 "release" [ ])
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
