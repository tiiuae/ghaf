# Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
{
  self,
  lib,
  microvm,
  lanzaboote,
  name,
  system,
  ...
}: let
  # From here
  # These can be added back to default.nix to form part of the target template
  debugModules = import ./debugModules.nix;
  releaseModules = import ./releaseModules.nix;

  ## To here

  lenovo-x1 = generation: variant: extraModules: let
    hwDefinition = import ../../modules/common/hardware/lenovo-x1/definitions {
      inherit generation lib;
    };
    hostConfiguration = lib.nixosSystem {
      inherit system;
      modules =
        [
          lanzaboote.nixosModules.lanzaboote
          microvm.nixosModules.host
          self.nixosModules.common
          self.nixosModules.desktop
          self.nixosModules.host
          self.nixosModules.lanzaboote
          self.nixosModules.microvm

          self.nixosModules.disko-lenovo-x1-basic-v1

          ./sshkeys.nix
          ({
            pkgs,
            config,
            ...
          }: let
            powerControl = pkgs.callPackage ../../packages/powercontrol {};
          in {
            security.polkit.extraConfig = powerControl.polkitExtraConfig;
            services.udev.extraRules = hwDefinition.udevRules;
            time.timeZone = "Asia/Dubai";

            # Enable pulseaudio support for host as a service
            sound.enable = true;
            hardware.pulseaudio.enable = true;
            hardware.pulseaudio.systemWide = true;
            # Add systemd to require pulseaudio before starting chromium-vm
            systemd.services."microvm@chromium-vm".after = ["pulseaudio.service"];
            systemd.services."microvm@chromium-vm".requires = ["pulseaudio.service"];

            # Allow microvm user to access pulseaudio
            hardware.pulseaudio.extraConfig = "load-module module-combine-sink module-native-protocol-unix auth-anonymous=1";
            users.extraUsers.microvm.extraGroups = ["audio" "pulse-access"];

            environment.etc.${config.ghaf.security.sshKeys.getAuthKeysFilePathInEtc} = import ./getAuthKeysSource.nix {inherit pkgs config;};
            services.openssh = config.ghaf.security.sshKeys.sshAuthorizedKeysCommand;

            disko.devices.disk = config.ghaf.hardware.definition.disks;

            ghaf = {
              hardware.definition = hwDefinition;
              # To enable guest hardening enable host hardening first
              host.kernel.hardening.enable = false;
              host.kernel.hardening.virtualization.enable = false;
              host.kernel.hardening.networking.enable = false;
              host.kernel.hardening.inputdevices.enable = false;

              guest.kernel.hardening.enable = false;
              guest.kernel.hardening.graphics.enable = false;

              host.kernel.hardening.hypervisor.enable = false;

              hardware.x86_64.common.enable = true;
              hardware.ax88179_178a.enable = true;

              security.tpm2.enable = true;

              virtualization.microvm-host.enable = true;
              virtualization.microvm-host.networkSupport = true;

              host.networking.enable = true;
              virtualization.microvm.netvm = {
                enable = true;
                extraModules = import ./netvmExtraModules.nix {
                  inherit lib pkgs microvm;
                  configH = config;
                };
              };
              virtualization.microvm.guivm = {
                enable = true;
                extraModules =
                  # TODO convert this to an actual module
                  import ./guivmExtraModules.nix {
                    inherit lib pkgs microvm;
                    configH = config;
                  };
              };
              virtualization.microvm.appvm = {
                enable = true;
                vms = import ./appvms/default.nix {inherit pkgs;};
              };

              # Enable all the default UI applications
              profiles = {
                applications.enable = false;
              };
              windows-launcher = {
                enable = true;
                spice = true;
              };
            };
          })

          #TODO: how to handle the majority of laptops that need a little
          # something extra?
          # SEE: https://github.com/NixOS/nixos-hardware/blob/master/flake.nix
          # nixos-hardware.nixosModules.lenovo-thinkpad-x1-10th-gen

          ({config, ...}: {
            boot.kernelParams = let
              filterDevices = builtins.filter (d: d.vendorId != null && d.productId != null);
              mapPciIdsToString = builtins.map (d: "${d.vendorId}:${d.productId}");
              vfioPciIds = mapPciIdsToString (filterDevices (
                config.ghaf.hardware.definition.network.pciDevices
                ++ config.ghaf.hardware.definition.gpu.pciDevices
              ));
            in [
              "intel_iommu=on,sm_on"
              "iommu=pt"
              # Prevent i915 module from being accidentally used by host
              "module_blacklist=i915"

              "vfio-pci.ids=${builtins.concatStringsSep "," vfioPciIds}"
            ];

            boot.initrd.availableKernelModules = ["nvme"];
          })
        ]
        ++ extraModules;
    };
  in {
    inherit hostConfiguration;
    name = "${name}-${generation}-${variant}";
    package = hostConfiguration.config.system.build.diskoImages;
  };
in [
  (lenovo-x1 "gen10" "debug" debugModules)
  (lenovo-x1 "gen11" "debug" debugModules)
  (lenovo-x1 "gen10" "release" releaseModules)
  (lenovo-x1 "gen11" "release" releaseModules)
]
