# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# Configuration for laptop devices based on the hardware and usecase profile
{
  lib,
  self,
  inputs,
  ...
}:
let
  system = "x86_64-linux";

  laptop-configuration = self.builders.mkLaptopConfiguration {
    inherit self inputs system;
    inherit (self) lib;
  };
  laptop-installer = self.builders.mkLaptopInstaller {
    inherit self system;
    inherit (self) lib;
  };

  # setup some commonality between the configurations
  commonModules = [
    self.nixosModules.disko-debug-partition
    self.nixosModules.verity-release-partition
    self.nixosModules.reference-profiles
    self.nixosModules.profiles
  ];

  # concatinate modules that are specific to a target
  withCommonModules = specificModules: specificModules ++ commonModules;

  installerModules = [
    (
      { config, ... }:
      {
        imports = [
          self.nixosModules.common
          self.nixosModules.givc
          self.nixosModules.development
          self.nixosModules.reference-personalize
        ];

        ghaf.host.secureboot.enable = true;

        users.users.nixos.openssh.authorizedKeys.keys =
          config.ghaf.reference.personalize.keys.authorizedSshKeys;
      }
    )
  ];
  target-configs = [
    # keep-sorted start skip_lines=1 block=yes newline_separated=yes by_regex=laptop-configuration\s*"(.*)"
    # Laptop Debug configurations
    (laptop-configuration "alienware-m18-R2" "debug" (withCommonModules [
      self.nixosModules.hardware-alienware-m18-r2
      {
        ghaf = {
          reference.profiles.mvp-user-trial.enable = true;
          partitioning.disko.enable = true;
          profiles.graphics.idleManagement.enable = false;
          profiles.graphics.allowSuspend = false;
        };
      }
    ]))

    (laptop-configuration "dell-latitude-7230" "debug" (withCommonModules [
      self.nixosModules.hardware-dell-latitude-7230
      {
        ghaf = {
          reference.profiles.mvp-user-trial.enable = true;
          partitioning.disko.enable = true;
        };
      }
    ]))

    (laptop-configuration "dell-latitude-7330" "debug" (withCommonModules [
      self.nixosModules.hardware-dell-latitude-7330
      {
        ghaf = {
          reference.profiles.mvp-user-trial.enable = true;
          partitioning.disko.enable = true;

          virtualization.microvm.guivm.extraModules = [
            {
              microvm.mem = lib.mkForce 6144;
            }
          ];
          virtualization.microvm.appvm.vms.flatpak.ramMb = lib.mkForce 5120;
        };
      }
    ]))

    (laptop-configuration "demo-tower-mk1" "debug" (withCommonModules [
      self.nixosModules.hardware-demo-tower-mk1
      {
        ghaf = {
          reference.profiles.mvp-user-trial.enable = true;
          partitioning.disko.enable = true;
          profiles.graphics.idleManagement.enable = false;
          services.performance.host.thermalLimitMode = "enabled";
        };
      }
    ]))

    # Generic target for Intel laptops with integrated graphics
    (laptop-configuration "intel-laptop" "debug" (withCommonModules [
      self.nixosModules.hardware-intel-laptop
      {
        ghaf = {
          reference.profiles.mvp-user-trial.enable = true;
          partitioning.disko.enable = true;
        };
      }
    ]))

    (laptop-configuration "lenovo-t14-amd-gen5" "debug" (withCommonModules [
      self.nixosModules.hardware-lenovo-t14-amd-gen5
      {
        ghaf = {
          reference.profiles.mvp-user-trial.enable = true;
          partitioning.disko.enable = true;
          services.performance.host.thermalLimitMode = "enabled";
        };
      }
    ]))

    (laptop-configuration "lenovo-x1-2-in-1-gen9" "debug" (withCommonModules [
      self.nixosModules.hardware-lenovo-x1-2-in-1-gen9
      {
        ghaf = {
          reference.profiles.mvp-user-trial.enable = true;
          partitioning.disko.enable = true;

          virtualization.microvm.guivm.extraModules = [
            {
              microvm.mem = lib.mkForce 2047;
            }
          ];
        };
      }
    ]))

    (laptop-configuration "lenovo-x1-carbon-gen10" "debug" (withCommonModules [
      self.nixosModules.hardware-lenovo-x1-carbon-gen10
      {
        ghaf = {
          reference.profiles.mvp-user-trial.enable = true;
          partitioning.disko.enable = true;
        };
      }
    ]))

    (laptop-configuration "lenovo-x1-carbon-gen11" "debug" (withCommonModules [
      self.nixosModules.hardware-lenovo-x1-carbon-gen11
      {
        ghaf = {
          reference.profiles.mvp-user-trial.enable = true;
          partitioning.disko.enable = true;
        };
      }
    ]))

    (laptop-configuration "lenovo-x1-carbon-gen12" "debug" (withCommonModules [
      self.nixosModules.hardware-lenovo-x1-carbon-gen12
      {
        ghaf = {
          reference.profiles.mvp-user-trial.enable = true;
          partitioning.disko.enable = true;
        };
      }
    ]))

    (laptop-configuration "lenovo-x1-carbon-gen13" "debug" (withCommonModules [
      self.nixosModules.hardware-lenovo-x1-carbon-gen13
      {
        ghaf = {
          reference.profiles.mvp-user-trial.enable = true;
          partitioning.disko.enable = true;
        };
      }
    ]))

    (laptop-configuration "lenovo-x1-extras" "debug" (withCommonModules [
      self.nixosModules.hardware-lenovo-x1-carbon-gen11
      {
        ghaf = {
          reference.profiles.mvp-user-trial-extras.enable = true;
          partitioning.disko.enable = true;
        };
      }
    ]))

    (laptop-configuration "lenovo-x1-gen11-hardening" "debug" (withCommonModules [
      self.nixosModules.hardware-lenovo-x1-carbon-gen11
      {
        ghaf = {
          # TODO profiles.kernel-hardening.enable = true;
          reference.profiles.mvp-user-trial-extras.enable = true;
          partitioning.verity.enable = true;
        };
      }
    ]))

    (laptop-configuration "system76-darp11-b" "debug" (withCommonModules [
      self.nixosModules.hardware-system76-darp11-b
      {
        ghaf = {
          reference.profiles.mvp-user-trial.enable = true;
          partitioning.disko.enable = true;
          profiles.graphics.idleManagement.enable = true;
          profiles.graphics.allowSuspend = false; # Suspension is broken (SSRCSP-7016)

          virtualization.microvm.guivm.extraModules = [
            {
              # We explicitly enable only those we need
              hardware.system76 = {
                power-daemon.enable = false;
                kernel-modules.enable = true;
                # Firmware daemon requires EFI mount point, not available in guivm
                firmware-daemon.enable = false;
              };
            }
          ];
        };
        # Add system76 and system76-io kernel modules to host
        hardware.system76.kernel-modules.enable = true;
      }
    ]))

    (laptop-configuration "system76-darp11-b-storeDisk" "debug" (withCommonModules [
      self.nixosModules.hardware-system76-darp11-b
      {
        ghaf = {
          reference.profiles.mvp-user-trial.enable = true;
          partitioning.disko.enable = true;
          profiles.graphics.idleManagement.enable = true;
          profiles.graphics.allowSuspend = false; # Suspension is broken (SSRCSP-7016)

          # Enable storeOnDisk for all VMs
          virtualization.microvm.storeOnDisk = true;

          virtualization.microvm.guivm.extraModules = [
            {
              # We explicitly enable only those we need
              hardware.system76 = {
                power-daemon.enable = false;
                kernel-modules.enable = true;
                # Firmware daemon requires EFI mount point, not available in guivm
                firmware-daemon.enable = false;
              };
            }
          ];
        };
        # Add system76 and system76-io kernel modules to host
        hardware.system76.kernel-modules.enable = true;
      }
    ]))

    (laptop-configuration "tower-5080" "debug" (withCommonModules [
      self.nixosModules.hardware-tower-5080
      {
        ghaf = {
          reference.profiles.mvp-user-trial.enable = true;
          partitioning.disko.enable = true;
          profiles.graphics.idleManagement.enable = false;
        };
      }
    ]))
    # keep-sorted end

    # keep-sorted start skip_lines=1 block=yes newline_separated=yes by_regex=laptop-configuration\s*"(.*)"
    # Laptop Release configurations
    (laptop-configuration "alienware-m18-R2" "release" (withCommonModules [
      self.nixosModules.hardware-alienware-m18-r2
      {
        ghaf = {
          reference.profiles.mvp-user-trial.enable = true;
          partitioning.disko.enable = true;
        };
      }
    ]))

    (laptop-configuration "dell-latitude-7230" "release" (withCommonModules [
      self.nixosModules.hardware-dell-latitude-7230
      {
        ghaf = {
          reference.profiles.mvp-user-trial.enable = true;
          partitioning.disko.enable = true;
        };
      }
    ]))

    (laptop-configuration "dell-latitude-7330" "release" (withCommonModules [
      self.nixosModules.hardware-dell-latitude-7330
      {
        ghaf = {
          reference.profiles.mvp-user-trial.enable = true;
          partitioning.disko.enable = true;

          virtualization.microvm.guivm.extraModules = [
            {
              microvm.mem = lib.mkForce 6144;
            }
          ];
          virtualization.microvm.appvm.vms.flatpak.ramMb = lib.mkForce 5120;
        };
      }
    ]))

    # Generic target for Intel laptops with integrated graphics
    (laptop-configuration "intel-laptop" "release" (withCommonModules [
      self.nixosModules.hardware-intel-laptop
      {
        ghaf = {
          reference.profiles.mvp-user-trial.enable = true;
          partitioning.disko.enable = true;
        };
      }
    ]))

    (laptop-configuration "lenovo-t14-amd-gen5" "release" (withCommonModules [
      self.nixosModules.hardware-lenovo-t14-amd-gen5
      {
        ghaf = {
          reference.profiles.mvp-user-trial.enable = true;
          partitioning.disko.enable = true;
          services.performance.host.thermalLimitMode = "enabled";
        };
      }
    ]))

    (laptop-configuration "lenovo-x1-carbon-gen10" "release" (withCommonModules [
      self.nixosModules.hardware-lenovo-x1-carbon-gen10
      {
        ghaf = {
          reference.profiles.mvp-user-trial.enable = true;
          partitioning.disko.enable = true;
        };
      }
    ]))

    (laptop-configuration "lenovo-x1-carbon-gen11" "release" (withCommonModules [
      self.nixosModules.hardware-lenovo-x1-carbon-gen11
      {
        ghaf = {
          reference.profiles.mvp-user-trial.enable = true;
          partitioning.disko.enable = true;
        };
      }
    ]))

    (laptop-configuration "lenovo-x1-carbon-gen12" "release" (withCommonModules [
      self.nixosModules.hardware-lenovo-x1-carbon-gen12
      {
        ghaf = {
          reference.profiles.mvp-user-trial.enable = true;
          partitioning.disko.enable = true;
        };
      }
    ]))

    (laptop-configuration "lenovo-x1-carbon-gen13" "release" (withCommonModules [
      self.nixosModules.hardware-lenovo-x1-carbon-gen13
      {
        ghaf = {
          reference.profiles.mvp-user-trial.enable = true;
          partitioning.disko.enable = true;
        };
      }
    ]))

    (laptop-configuration "lenovo-x1-extras" "release" (withCommonModules [
      self.nixosModules.hardware-lenovo-x1-carbon-gen11
      {
        ghaf = {
          reference.profiles.mvp-user-trial-extras.enable = true;
          partitioning.disko.enable = true;
        };
      }
    ]))

    (laptop-configuration "lenovo-x1-gen11-hardening" "release" (withCommonModules [
      self.nixosModules.hardware-lenovo-x1-carbon-gen11
      {
        ghaf = {
          # TODO profiles.kernel-hardening.enable = true;
          reference.profiles.mvp-user-trial-extras.enable = true;
          partitioning.verity.enable = true;
        };
      }
    ]))

    (laptop-configuration "system76-darp11-b" "release" (withCommonModules [
      self.nixosModules.hardware-system76-darp11-b
      {
        ghaf = {
          reference.profiles.mvp-user-trial.enable = true;
          partitioning.disko.enable = true;
          profiles.graphics.idleManagement.enable = true;
          profiles.graphics.allowSuspend = false; # Suspension is broken (SSRCSP-7016)

          virtualization.microvm.guivm.extraModules = [
            {
              # We explicitly enable only those we need
              hardware.system76 = {
                power-daemon.enable = false;
                kernel-modules.enable = true;
                # Firmware daemon requires EFI mount point, not available in guivm
                firmware-daemon.enable = false;
              };
            }
          ];
        };
        # Add system76 and system76-io kernel modules to host
        hardware.system76.kernel-modules.enable = true;
      }
    ]))
    # keep-sorted end
  ];

  # map all of the defined configurations to an installer image
  target-installers = map (
    t: laptop-installer t.name self.packages.x86_64-linux.${t.name} installerModules
  ) target-configs;

  targets = target-configs ++ target-installers;
in
{
  flake = {
    nixosConfigurations = builtins.listToAttrs (
      map (t: lib.nameValuePair t.name t.hostConfiguration) targets
    );
    packages.${system} = builtins.listToAttrs (map (t: lib.nameValuePair t.name t.package) targets);
  };
}
