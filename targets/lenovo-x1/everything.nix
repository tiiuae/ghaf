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
  lenovo-x1 = generation: variant: extraModules: let
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

          ({
            pkgs,
            config,
            ...
          }: let
            powerControl = pkgs.callPackage ../../packages/powercontrol {};

            # TODO: Move this to a separate function in self.lib
            filterDevices = builtins.filter (d: d.vendorId != null && d.productId != null);
            mapPciIdsToString = builtins.map (d: "${d.vendorId}:${d.productId}");
            vfioPciIds = mapPciIdsToString (filterDevices (
              config.ghaf.hardware.definition.network.pciDevices
              ++ config.ghaf.hardware.definition.gpu.pciDevices
            ));
          in {
            boot.kernelParams = [
              "intel_iommu=on,sm_on"
              "iommu=pt"
              # Prevent i915 module from being accidentally used by host
              "module_blacklist=i915"
              "acpi_backlight=vendor"
              # Enable VFIO for PCI devices
              "vfio-pci.ids=${builtins.concatStringsSep "," vfioPciIds}"
            ];

            boot.initrd.availableKernelModules = ["nvme"];

            security.polkit.extraConfig = powerControl.polkitExtraConfig;
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

            disko.devices.disk = config.ghaf.hardware.definition.disks;

            ghaf = {
              # variant type, turn on debug or release
              profiles.debug.enable = variant == "debug";
              profiles.release.enable = variant == "release";

              # Hardware definitions
              hardware.x86_64.common.enable = true;
              hardware.generation = generation;
              hardware.tpm2.enable = true;
              hardware.fprint.enable = true;

              # Virtualization options
              virtualization.microvm-host.enable = true;
              virtualization.microvm-host.networkSupport = true;

              host.networking.enable = true;
              host.powercontrol.enable = true;
              # dendrite-pinecone service is enabled
              services.dendrite-pinecone.enable = true;

              virtualization.microvm.netvm = {
                enable = true;
                extraModules = import ./netvmExtraModules.nix {
                  inherit lib pkgs microvm;
                  configH = config;
                };
              };

              virtualization.microvm.adminvm = {
                enable = true;
              };

              virtualization.microvm.idsvm = {
                enable = false;
                mitmproxy.enable = false;
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
                vms = import ./appvms/default.nix {inherit pkgs lib config;};
              };

              # UI applications
              profiles = {
                applications.enable = false;
              };

              windows-launcher = {
                enable = true;
                spice = true;
              };
            };
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
  (lenovo-x1 "gen10" "debug" [self.nixosModules.disko-lenovo-x1-basic-v1 self.nixosModules.hw-lenovo-x1])
  (lenovo-x1 "gen11" "debug" [self.nixosModules.disko-lenovo-x1-basic-v1 self.nixosModules.hw-lenovo-x1])
  (lenovo-x1 "gen10" "release" [self.nixosModules.disko-lenovo-x1-basic-v1 self.nixosModules.hw-lenovo-x1])
  (lenovo-x1 "gen11" "release" [self.nixosModules.disko-lenovo-x1-basic-v1 self.nixosModules.hw-lenovo-x1])
]
