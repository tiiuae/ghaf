# Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# Generic x86_64 computer -target
{
  inputs,
  lib,
  self,
  ...
}: let
  inherit (inputs) microvm nixos-generators;
  name = "generic-x86_64";
  system = "x86_64-linux";
  generic-x86 = variant: extraModules: let
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
        services.dnsmasq.settings.dhcp-option = [
          "option:router,192.168.100.1" # set net-vm as a default gw
          "option:dns-server,192.168.100.1"
        ];
      }
    ];
    hostConfiguration = lib.nixosSystem {
      inherit system;
      modules =
        [
          microvm.nixosModules.host
          nixos-generators.nixosModules.raw-efi
          self.nixosModules.common
          self.nixosModules.desktop
          self.nixosModules.host
          self.nixosModules.microvm
          self.nixosModules.hw-x86_64-generic
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
                applications.enable = true;
                release.enable = variant == "release";
                debug.enable = variant == "debug";
                # Uncomment this line to use Labwc instead of Weston:
                #graphics.compositor = "labwc";
              };
              reference.programs.windows-launcher.enable = true;
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
  in {
    inherit hostConfiguration;
    name = "${name}-${variant}";
    package = hostConfiguration.config.system.build.${hostConfiguration.config.formatAttr};
  };
  debugModules = [{ghaf.development.usb-serial.enable = true;}];
  targets = [
    (generic-x86 "debug" debugModules)
    (generic-x86 "release" [])
  ];
in {
  flake = {
    nixosConfigurations =
      builtins.listToAttrs (map (t: lib.nameValuePair t.name t.hostConfiguration) targets);
    packages = {
      x86_64-linux =
        builtins.listToAttrs (map (t: lib.nameValuePair t.name t.package) targets);
    };
  };
}
