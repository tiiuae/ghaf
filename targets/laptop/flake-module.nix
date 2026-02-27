# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# Configuration for laptop devices based on the hardware and usecase profile
#
{
  lib,
  self,
  inputs,
  ...
}:
let
  system = "x86_64-linux";

  # Unified Ghaf configuration builder
  ghaf-configuration = self.builders.mkGhafConfiguration {
    inherit self inputs;
    inherit (self) lib;
  };

  # Unified Ghaf installer builder
  ghaf-installer = self.builders.mkGhafInstaller {
    inherit self system;
    inherit (self) lib;
  };

  # Common modules shared across all laptop configurations
  commonModules = [
    self.nixosModules.disko-debug-partition
    self.nixosModules.verity-release-partition
    self.nixosModules.reference-profiles
    self.nixosModules.profiles
  ];

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

  # All laptop configurations using mkGhafConfiguration
  target-configs = [
    # ============================================================
    # Debug Configurations
    # ============================================================
    # keep-sorted start block=yes skip_lines=1 newline_separated=yes by_regex=\sname\s=\s\"(.*)\"

    (ghaf-configuration {
      name = "alienware-m18-R2";
      inherit system;
      profile = "laptop-x86";
      hardwareModule = self.nixosModules.hardware-alienware-m18-r2;
      variant = "debug";
      extraModules = commonModules;
      extraConfig = {
        reference.profiles.mvp-user-trial.enable = true;
        partitioning.disko.enable = true;
        services.power-manager.suspend.enable = false;
      };
    })

    (ghaf-configuration {
      name = "dell-latitude-7230";
      inherit system;
      profile = "laptop-x86";
      hardwareModule = self.nixosModules.hardware-dell-latitude-7230;
      variant = "debug";
      extraModules = commonModules;
      extraConfig = {
        reference.profiles.mvp-user-trial.enable = true;
        partitioning.disko.enable = true;
      };
    })

    (ghaf-configuration {
      name = "dell-latitude-7330";
      inherit system;
      profile = "laptop-x86";
      hardwareModule = self.nixosModules.hardware-dell-latitude-7330;
      variant = "debug";
      extraModules = commonModules;
      extraConfig = {
        reference.profiles.mvp-user-trial.enable = true;
        partitioning.disko.enable = true;
        # Enable PCI ACS override to split IOMMU groups
        # Needed to separate Ethernet (8086:15fb) from Audio devices
        hardware.passthrough.pciAcsOverride = {
          enable = true;
          ids = [ "8086:15fb" ];
        };
      };
      vmConfig = {
        sysvms.guivm.mem = 6144;
        appvms.flatpak.mem = 5120;
      };
    })

    (ghaf-configuration {
      name = "demo-tower-mk1";
      inherit system;
      profile = "laptop-x86";
      hardwareModule = self.nixosModules.hardware-demo-tower-mk1;
      variant = "debug";
      extraModules = commonModules;
      extraConfig = {
        reference.profiles.mvp-user-trial.enable = true;
        partitioning.disko.enable = true;
        services.performance.host.thermalLimitMode = "enabled";
      };
    })

    (ghaf-configuration {
      name = "intel-laptop";
      inherit system;
      profile = "laptop-x86";
      hardwareModule = self.nixosModules.hardware-intel-laptop;
      variant = "debug";
      extraModules = commonModules;
      extraConfig = {
        reference.profiles.mvp-user-trial.enable = true;
        partitioning.disko.enable = true;
      };
    })

    (ghaf-configuration {
      name = "intel-laptop-low-mem";
      inherit system;
      profile = "laptop-x86";
      hardwareModule = self.nixosModules.hardware-intel-laptop;
      variant = "debug";
      extraModules = commonModules;
      extraConfig = {
        reference.profiles.mvp-user-trial.enable = true;
        partitioning.disko.enable = true;
      };
      vmConfig = {
        sysvms.guivm.mem = 6144;
        appvms.flatpak.mem = 5120;
      };
    })

    (ghaf-configuration {
      name = "lenovo-t14-amd-gen5";
      inherit system;
      profile = "laptop-x86";
      hardwareModule = self.nixosModules.hardware-lenovo-t14-amd-gen5;
      variant = "debug";
      extraModules = commonModules;
      extraConfig = {
        reference.profiles.mvp-user-trial.enable = true;
        partitioning.disko.enable = true;
        services.performance.host.thermalLimitMode = "enabled";
      };
    })

    (ghaf-configuration {
      name = "lenovo-x1-2-in-1-gen9";
      inherit system;
      profile = "laptop-x86";
      hardwareModule = self.nixosModules.hardware-lenovo-x1-2-in-1-gen9;
      variant = "debug";
      extraModules = commonModules;
      extraConfig = {
        reference.profiles.mvp-user-trial.enable = true;
        partitioning.disko.enable = true;
      };
      vmConfig = {
        sysvms.guivm.mem = 2047;
      };
    })

    (ghaf-configuration {
      name = "lenovo-x1-carbon-gen10";
      inherit system;
      profile = "laptop-x86";
      hardwareModule = self.nixosModules.hardware-lenovo-x1-carbon-gen10;
      variant = "debug";
      extraModules = commonModules;
      extraConfig = {
        reference.profiles.mvp-user-trial.enable = true;
        partitioning.disko.enable = true;
      };
    })

    (ghaf-configuration {
      name = "lenovo-x1-carbon-gen11";
      inherit system;
      profile = "laptop-x86";
      hardwareModule = self.nixosModules.hardware-lenovo-x1-carbon-gen11;
      variant = "debug";
      extraModules = commonModules;
      extraConfig = {
        reference.profiles.mvp-user-trial.enable = true;
        partitioning.disko.enable = true;
      };
    })

    (ghaf-configuration {
      name = "lenovo-x1-carbon-gen12";
      inherit system;
      profile = "laptop-x86";
      hardwareModule = self.nixosModules.hardware-lenovo-x1-carbon-gen12;
      variant = "debug";
      extraModules = commonModules;
      extraConfig = {
        reference.profiles.mvp-user-trial.enable = true;
        partitioning.disko.enable = true;
      };
    })

    (ghaf-configuration {
      name = "lenovo-x1-carbon-gen13";
      inherit system;
      profile = "laptop-x86";
      hardwareModule = self.nixosModules.hardware-lenovo-x1-carbon-gen13;
      variant = "debug";
      extraModules = commonModules;
      extraConfig = {
        reference.profiles.mvp-user-trial.enable = true;
        partitioning.disko.enable = true;
      };
    })

    (ghaf-configuration {
      name = "lenovo-x1-extras";
      inherit system;
      profile = "laptop-x86";
      hardwareModule = self.nixosModules.hardware-lenovo-x1-carbon-gen11;
      variant = "debug";
      extraModules = commonModules;
      extraConfig = {
        reference.profiles.mvp-user-trial-extras.enable = true;
        partitioning.disko.enable = true;
      };
    })

    (ghaf-configuration {
      name = "lenovo-x1-gen11-hardening";
      inherit system;
      profile = "laptop-x86";
      hardwareModule = self.nixosModules.hardware-lenovo-x1-carbon-gen11;
      variant = "debug";
      extraModules = commonModules;
      extraConfig = {
        # TODO profiles.kernel-hardening.enable = true;
        reference.profiles.mvp-user-trial-extras.enable = true;
        partitioning.verity.enable = true;
      };
    })

    (ghaf-configuration {
      name = "system76-darp11-b";
      inherit system;
      profile = "laptop-x86";
      hardwareModule = self.nixosModules.hardware-system76-darp11-b;
      variant = "debug";
      extraModules = commonModules ++ [
        {
          # Add system76 and system76-io kernel modules to host
          hardware.system76.kernel-modules.enable = true;
        }
      ];
      extraConfig = {
        reference.profiles.mvp-user-trial.enable = true;
        partitioning.disko.enable = true;
        services.power-manager.suspend.mode = "s2idle";
        # Enable PCI ACS override to split IOMMU groups
        # Needed to separate Ethernet (8086:550a) from Audio devices
        hardware.passthrough.pciAcsOverride = {
          enable = true;
          ids = [ "8086:550a" ];
        };
        # Hardware-specific VM configs via hardware definition
        hardware.definition.guivm.extraModules = [
          {
            hardware.system76 = {
              power-daemon.enable = false;
              kernel-modules.enable = true;
              firmware-daemon.enable = false;
            };
          }
        ];
      };
    })

    (ghaf-configuration {
      name = "system76-darp11-b-storeDisk";
      inherit system;
      profile = "laptop-x86";
      hardwareModule = self.nixosModules.hardware-system76-darp11-b;
      variant = "debug";
      extraModules = commonModules ++ [
        {
          hardware.system76.kernel-modules.enable = true;
        }
      ];
      extraConfig = {
        reference.profiles.mvp-user-trial.enable = true;
        partitioning.disko.enable = true;
        services.power-manager.suspend.mode = "s2idle";
        virtualization.microvm.storeOnDisk = true;
        hardware.passthrough.pciAcsOverride = {
          enable = true;
          ids = [ "8086:550a" ];
        };
        hardware.definition.guivm.extraModules = [
          {
            hardware.system76 = {
              power-daemon.enable = false;
              kernel-modules.enable = true;
              firmware-daemon.enable = false;
            };
          }
        ];
      };
    })

    (ghaf-configuration {
      name = "tower-5080";
      inherit system;
      profile = "laptop-x86";
      hardwareModule = self.nixosModules.hardware-tower-5080;
      variant = "debug";
      extraModules = commonModules;
      extraConfig = {
        reference.profiles.mvp-user-trial.enable = true;
        partitioning.disko.enable = true;
      };
    })
    # keep-sorted end

    # ============================================================
    # Release Configurations
    # ============================================================
    # keep-sorted start block=yes skip_lines=1 newline_separated=yes by_regex=\sname\s=\s\"(.*)\"

    (ghaf-configuration {
      name = "alienware-m18-R2";
      inherit system;
      profile = "laptop-x86";
      hardwareModule = self.nixosModules.hardware-alienware-m18-r2;
      variant = "release";
      extraModules = commonModules;
      extraConfig = {
        reference.profiles.mvp-user-trial.enable = true;
        partitioning.disko.enable = true;
      };
    })

    (ghaf-configuration {
      name = "dell-latitude-7230";
      inherit system;
      profile = "laptop-x86";
      hardwareModule = self.nixosModules.hardware-dell-latitude-7230;
      variant = "release";
      extraModules = commonModules;
      extraConfig = {
        reference.profiles.mvp-user-trial.enable = true;
        partitioning.disko.enable = true;
      };
    })

    (ghaf-configuration {
      name = "dell-latitude-7330";
      inherit system;
      profile = "laptop-x86";
      hardwareModule = self.nixosModules.hardware-dell-latitude-7330;
      variant = "release";
      extraModules = commonModules;
      extraConfig = {
        reference.profiles.mvp-user-trial.enable = true;
        partitioning.disko.enable = true;
        hardware.passthrough.pciAcsOverride = {
          enable = true;
          ids = [ "8086:15fb" ];
        };
      };
      vmConfig = {
        sysvms.guivm.mem = 6144;
        appvms.flatpak.mem = 5120;
      };
    })

    (ghaf-configuration {
      name = "intel-laptop";
      inherit system;
      profile = "laptop-x86";
      hardwareModule = self.nixosModules.hardware-intel-laptop;
      variant = "release";
      extraModules = commonModules;
      extraConfig = {
        reference.profiles.mvp-user-trial.enable = true;
        partitioning.disko.enable = true;
      };
    })

    (ghaf-configuration {
      name = "intel-laptop-low-mem";
      inherit system;
      profile = "laptop-x86";
      hardwareModule = self.nixosModules.hardware-intel-laptop;
      variant = "release";
      extraModules = commonModules;
      extraConfig = {
        reference.profiles.mvp-user-trial.enable = true;
        partitioning.disko.enable = true;
      };
      vmConfig = {
        sysvms.guivm.mem = 6144;
        appvms.flatpak.mem = 5120;
      };
    })

    (ghaf-configuration {
      name = "lenovo-t14-amd-gen5";
      inherit system;
      profile = "laptop-x86";
      hardwareModule = self.nixosModules.hardware-lenovo-t14-amd-gen5;
      variant = "release";
      extraModules = commonModules;
      extraConfig = {
        reference.profiles.mvp-user-trial.enable = true;
        partitioning.disko.enable = true;
        services.performance.host.thermalLimitMode = "enabled";
      };
    })

    (ghaf-configuration {
      name = "lenovo-x1-carbon-gen10";
      inherit system;
      profile = "laptop-x86";
      hardwareModule = self.nixosModules.hardware-lenovo-x1-carbon-gen10;
      variant = "release";
      extraModules = commonModules;
      extraConfig = {
        reference.profiles.mvp-user-trial.enable = true;
        partitioning.disko.enable = true;
      };
    })

    (ghaf-configuration {
      name = "lenovo-x1-carbon-gen11";
      inherit system;
      profile = "laptop-x86";
      hardwareModule = self.nixosModules.hardware-lenovo-x1-carbon-gen11;
      variant = "release";
      extraModules = commonModules;
      extraConfig = {
        reference.profiles.mvp-user-trial.enable = true;
        partitioning.disko.enable = true;
      };
    })

    (ghaf-configuration {
      name = "lenovo-x1-carbon-gen12";
      inherit system;
      profile = "laptop-x86";
      hardwareModule = self.nixosModules.hardware-lenovo-x1-carbon-gen12;
      variant = "release";
      extraModules = commonModules;
      extraConfig = {
        reference.profiles.mvp-user-trial.enable = true;
        partitioning.disko.enable = true;
      };
    })

    (ghaf-configuration {
      name = "lenovo-x1-carbon-gen13";
      inherit system;
      profile = "laptop-x86";
      hardwareModule = self.nixosModules.hardware-lenovo-x1-carbon-gen13;
      variant = "release";
      extraModules = commonModules;
      extraConfig = {
        reference.profiles.mvp-user-trial.enable = true;
        partitioning.disko.enable = true;
      };
    })

    (ghaf-configuration {
      name = "lenovo-x1-extras";
      inherit system;
      profile = "laptop-x86";
      hardwareModule = self.nixosModules.hardware-lenovo-x1-carbon-gen11;
      variant = "release";
      extraModules = commonModules;
      extraConfig = {
        reference.profiles.mvp-user-trial-extras.enable = true;
        partitioning.disko.enable = true;
      };
    })

    (ghaf-configuration {
      name = "lenovo-x1-gen11-hardening";
      inherit system;
      profile = "laptop-x86";
      hardwareModule = self.nixosModules.hardware-lenovo-x1-carbon-gen11;
      variant = "release";
      extraModules = commonModules;
      extraConfig = {
        # TODO profiles.kernel-hardening.enable = true;
        reference.profiles.mvp-user-trial-extras.enable = true;
        partitioning.verity.enable = true;
      };
    })

    (ghaf-configuration {
      name = "system76-darp11-b";
      inherit system;
      profile = "laptop-x86";
      hardwareModule = self.nixosModules.hardware-system76-darp11-b;
      variant = "release";
      extraModules = commonModules ++ [
        {
          hardware.system76.kernel-modules.enable = true;
        }
      ];
      extraConfig = {
        reference.profiles.mvp-user-trial.enable = true;
        partitioning.disko.enable = true;
        services.power-manager.suspend.mode = "s2idle";
        hardware.passthrough.pciAcsOverride = {
          enable = true;
          ids = [ "8086:550a" ];
        };
        hardware.definition.guivm.extraModules = [
          {
            hardware.system76 = {
              power-daemon.enable = false;
              kernel-modules.enable = true;
              firmware-daemon.enable = false;
            };
          }
        ];
      };
    })

    (ghaf-configuration {
      name = "system76-darp11-b-storeDisk";
      inherit system;
      profile = "laptop-x86";
      hardwareModule = self.nixosModules.hardware-system76-darp11-b;
      variant = "release";
      extraModules = commonModules ++ [
        {
          hardware.system76.kernel-modules.enable = true;
        }
      ];
      extraConfig = {
        reference.profiles.mvp-user-trial.enable = true;
        partitioning.disko.enable = true;
        services.power-manager.suspend.mode = "s2idle";
        virtualization.microvm.storeOnDisk = true;
        hardware.passthrough.pciAcsOverride = {
          enable = true;
          ids = [ "8086:550a" ];
        };
        hardware.definition.guivm.extraModules = [
          {
            hardware.system76 = {
              power-daemon.enable = false;
              kernel-modules.enable = true;
              firmware-daemon.enable = false;
            };
          }
        ];
      };
    })
    # keep-sorted end
  ];

  # Map all of the defined configurations to an installer image
  target-installers = map (
    t:
    ghaf-installer {
      inherit (t) name;
      imagePath = self.packages.x86_64-linux.${t.name};
      extraModules = installerModules;
    }
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
