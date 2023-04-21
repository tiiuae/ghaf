# Copyright 2022-2023 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# Generic x86_64 computer -target
{
  self,
  nixpkgs,
  nixos-generators,
  nixos-hardware,
  microvm,
}: let
  name = "generic-x86_64";
  system = "x86_64-linux";
  formatModule = nixos-generators.nixosModules.raw-efi;
  generic-x86 = variant: extraModules: let
    hostConfiguration = nixpkgs.lib.nixosSystem {
      inherit system;
      modules =
        [
          (import ../modules/host {
            inherit self microvm netvm guivm;
          })

          ../modules/hardware/x86_64-linux.nix

          ./common-${variant}.nix

          ../modules/graphics/weston.nix

          formatModule

          #TODO: how to handle the majority of laptops that need a little
          # something extra?
          # SEE: https://github.com/NixOS/nixos-hardware/blob/master/flake.nix
          # nixos-hardware.nixosModules.lenovo-thinkpad-x1-10th-gen

          {
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
    netvm = "netvm-${name}-${variant}";
    guivm = "guivm-${name}-${variant}";
  in {
    inherit hostConfiguration netvm guivm;
    name = "${name}-${variant}";
    netvmConfiguration =
      (import ../microvmConfigurations/netvm {
        inherit nixpkgs microvm system;
      })
      .extendModules {
        modules = [
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
      };
    guivmConfiguration =
      (import ../microvmConfigurations/guivm {
        inherit nixpkgs microvm system;
      })
      .extendModules {
        modules = [
          {
            microvm.devices = [
              {
                bus = "pci";
                path = "0005:01:00.0";
              }
              {
                bus = "pci";
                path = "0005:01:00.1";
              }
            ];
          }
        ];
      };
    package = hostConfiguration.config.system.build.${hostConfiguration.config.formatAttr};
  };
  debugModules = [../modules/development/usb-serial.nix];
  targets = [
    (generic-x86 "debug" debugModules)
    (generic-x86 "release" [])
  ];
in {
  nixosConfigurations =
    builtins.listToAttrs (map (t: nixpkgs.lib.nameValuePair t.name t.hostConfiguration) targets)
    // builtins.listToAttrs (map (t: nixpkgs.lib.nameValuePair t.netvm t.netvmConfiguration) targets);
  packages = {
    x86_64-linux =
      builtins.listToAttrs (map (t: nixpkgs.lib.nameValuePair t.name t.package) targets);
  };
}
