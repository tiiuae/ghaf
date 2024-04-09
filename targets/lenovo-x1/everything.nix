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
              ++ config.ghaf.hardware.definition.audio.pciDevices
            ));
          in {
            boot = {
              kernelParams = [
                "intel_iommu=on,sm_on"
                "iommu=pt"
                # Prevent i915 module from being accidentally used by host
                "module_blacklist=i915"
                "acpi_backlight=vendor"
                # Enable VFIO for PCI devices
                "vfio-pci.ids=${builtins.concatStringsSep "," vfioPciIds}"
              ];

              initrd.availableKernelModules = ["nvme"];
            };

            security.polkit = {
              enable = true;
              extraConfig = powerControl.polkitExtraConfig;
            };
            time.timeZone = "Asia/Dubai";

            systemd.services."microvm@audio-vm".serviceConfig = {
              # The + here is a systemd feature to make the script run as root.
              ExecStopPost = [
                "+${pkgs.writeShellScript "reload-audio" ''
                  # The script makes audio device internal state to reset
                  # This fixes issue of audio device getting into some unexpected
                  # state when the VM is being shutdown during audio mic recording
                  echo "1" > /sys/bus/pci/devices/0000:00:1f.3/remove
                  sleep 0.1
                  echo "1" > /sys/bus/pci/devices/0000:00:1f.0/rescan
                ''}"
              ];
            };

            disko.devices.disk = config.ghaf.hardware.definition.disks;

            ghaf = {
              # variant type, turn on debug or release
              profiles = {
                debug.enable = variant == "debug";
                release.enable = variant == "release";
              };

              # Hardware definitions
              hardware = {
                inherit generation;
                x86_64.common.enable = true;
                tpm2.enable = true;
                fprint.enable = true;
              };

              # Virtualization options
              virtualization = {
                microvm-host = {
                  enable = true;
                  networkSupport = true;
                };

                microvm = {
                  netvm = {
                    enable = true;
                    extraModules = import ./netvmExtraModules.nix {
                      inherit lib pkgs microvm;
                      configH = config;
                    };
                  };

                  adminvm = {
                    enable = true;
                  };

                  idsvm = {
                    enable = false;
                    mitmproxy.enable = false;
                  };

                  guivm = {
                    enable = true;
                    extraModules =
                      # TODO convert this to an actual module
                      import ./guivmExtraModules.nix {
                        inherit lib pkgs microvm;
                        configH = config;
                      };
                  };

                  audiovm = {
                    enable = true;
                    extraModules = import ./audiovmExtraModules.nix {
                      inherit lib pkgs microvm;
                      configH = config;
                    };
                  };

                  appvm = {
                    enable = true;
                    vms = import ./appvms/default.nix {inherit pkgs lib config;};
                  };
                };
              };

              host = {
                networking.enable = true;
                powercontrol.enable = true;
              };
              # dendrite-pinecone service is enabled
              services.dendrite-pinecone.enable = true;

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
