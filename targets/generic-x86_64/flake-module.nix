# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# Generic x86_64 computer -target
{
  lib,
  self,
  ...
}:
let
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

          # For WLAN firmwares
          hardware.enableRedistributableFirmware = true;

          networking.wireless = {
            enable = true;

            # networks."SSID_OF_NETWORK".psk = "WPA_PASSWORD";
          };
        }
      ];
      hostConfiguration = lib.nixosSystem {
        specialArgs = {
          inherit (self) lib;
        };
        modules = [
          # Use nixpkgs disk-image module for raw EFI image generation
          (
            {
              lib,
              config,
              pkgs,
              modulesPath,
              ...
            }:
            {
              imports = [ "${modulesPath}/virtualisation/disk-image.nix" ];

              image.format = "raw";

              # Override image to add zstd compression
              system.build.image = lib.mkOverride 98 (
                import "${toString modulesPath}/../lib/make-disk-image.nix" {
                  inherit lib config pkgs;
                  partitionTableType = "efi";
                  inherit (config.virtualisation) diskSize;
                  format = "raw";
                  postVM = "${pkgs.zstd}/bin/zstd --compress --rm $out/nixos.img";
                }
              );
            }
          )
          self.nixosModules.microvm
          self.nixosModules.hardware-x86_64-generic
          self.nixosModules.profiles
          self.nixosModules.reference-host-demo-apps
          self.nixosModules.reference-programs

          {
            ghaf = {
              hardware.x86_64.common.enable = true;

              virtualization = {
                microvm-host = {
                  enable = true;
                  networkSupport = true;
                };

                microvm.netvm = {
                  enable = true;
                  extraModules = netvmExtraModules;
                };
              };

              host.networking.enable = true;

              # Enable all the default UI applications
              profiles = {
                graphics.enable = true;
                release.enable = variant == "release";
                debug.enable = variant == "debug";
                # Uncomment this line to use Labwc instead of Cosmic:
                # graphics.compositor = "labwc";
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
      package = hostConfiguration.config.system.build.image;
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
