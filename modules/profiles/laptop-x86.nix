# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  config,
  lib,
  inputs,
  ...
}:
let
  cfg = config.ghaf.profiles.laptop-x86;
  hostGlobalConfig = config.ghaf.global-config;
in
{
  options.ghaf.profiles.laptop-x86 = {
    enable = lib.mkEnableOption "Enable the basic x86 laptop config";

    # GUI VM base configuration for profiles to extend
    guivmBase = lib.mkOption {
      type = lib.types.unspecified;
      readOnly = true;
      description = ''
        Laptop-x86 GUI VM base configuration.
        Profiles should extend this with extendModules to add services.
      '';
    };

    # Admin VM base configuration for profiles to extend
    adminvmBase = lib.mkOption {
      type = lib.types.unspecified;
      readOnly = true;
      description = ''
        Laptop-x86 Admin VM base configuration.
        Profiles can extend this with extendModules if customization needed.
      '';
    };

    # IDS VM base configuration for profiles to extend
    idsvmBase = lib.mkOption {
      type = lib.types.unspecified;
      readOnly = true;
      description = ''
        Laptop-x86 IDS VM base configuration.
        Profiles can extend this with extendModules if customization needed.
      '';
    };

    # Audio VM base configuration for profiles to extend
    audiovmBase = lib.mkOption {
      type = lib.types.unspecified;
      readOnly = true;
      description = ''
        Laptop-x86 Audio VM base configuration.
        Profiles can extend this with extendModules if customization needed.
      '';
    };

    # Net VM base configuration for profiles to extend
    netvmBase = lib.mkOption {
      type = lib.types.unspecified;
      readOnly = true;
      description = ''
        Laptop-x86 Net VM base configuration.
        Profiles can extend this with extendModules if customization needed.
      '';
    };

    # App VM factory function for creating app VMs
    mkAppVm = lib.mkOption {
      type = lib.types.unspecified;
      readOnly = true;
      description = ''
        Function to create an App VM configuration.
        Takes a VM definition and returns a nixosSystem that can be extended.

        Example:
          mkAppVm {
            name = "chromium";
            ramMb = 6144;
            cores = 4;
            applications = [ { name = "Chromium"; command = "chromium"; ... } ];
          }

        The result can be extended with:
          (mkAppVm vmDef).extendModules { modules = [ ... ]; }
      '';
    };
  };

  config = lib.mkIf cfg.enable {

    # Export GUI VM base for profiles to extend
    ghaf.profiles.laptop-x86.guivmBase = lib.nixosSystem {
      inherit (inputs.nixpkgs.legacyPackages.x86_64-linux) system;
      modules = [
        inputs.microvm.nixosModules.microvm
        inputs.self.nixosModules.guivm-base
        # Import nixpkgs config module to get overlays
        {
          nixpkgs.overlays = config.nixpkgs.overlays;
          nixpkgs.config = config.nixpkgs.config;
        }
      ];
      specialArgs = lib.ghaf.vm.mkSpecialArgs {
        inherit lib inputs;
        globalConfig = hostGlobalConfig;
        hostConfig = lib.ghaf.vm.mkHostConfig {
          inherit config;
          vmName = "gui-vm";
        };
      };
    };

    # Export Admin VM base for profiles to extend
    ghaf.profiles.laptop-x86.adminvmBase = lib.nixosSystem {
      inherit (inputs.nixpkgs.legacyPackages.x86_64-linux) system;
      modules = [
        inputs.microvm.nixosModules.microvm
        inputs.self.nixosModules.adminvm-base
        inputs.self.nixosModules.adminvm-features
        # Import nixpkgs config module to get overlays
        {
          nixpkgs.overlays = config.nixpkgs.overlays;
          nixpkgs.config = config.nixpkgs.config;
        }
      ];
      specialArgs = lib.ghaf.vm.mkSpecialArgs {
        inherit lib inputs;
        globalConfig = hostGlobalConfig;
        hostConfig = lib.ghaf.vm.mkHostConfig {
          inherit config;
          vmName = "admin-vm";
        };
      };
    };

    # Export IDS VM base for profiles to extend
    ghaf.profiles.laptop-x86.idsvmBase = lib.nixosSystem {
      inherit (inputs.nixpkgs.legacyPackages.x86_64-linux) system;
      modules = [
        inputs.microvm.nixosModules.microvm
        inputs.self.nixosModules.idsvm-base
        # Import nixpkgs config module to get overlays
        {
          nixpkgs.overlays = config.nixpkgs.overlays;
          nixpkgs.config = config.nixpkgs.config;
        }
      ];
      specialArgs = lib.ghaf.vm.mkSpecialArgs {
        inherit lib inputs;
        globalConfig = hostGlobalConfig;
        hostConfig = lib.ghaf.vm.mkHostConfig {
          inherit config;
          vmName = "ids-vm";
        };
      };
    };

    # Export Audio VM base for profiles to extend
    ghaf.profiles.laptop-x86.audiovmBase = lib.nixosSystem {
      inherit (inputs.nixpkgs.legacyPackages.x86_64-linux) system;
      modules = [
        inputs.microvm.nixosModules.microvm
        inputs.self.nixosModules.audiovm-base
        # Import nixpkgs config module to get overlays
        {
          nixpkgs.overlays = config.nixpkgs.overlays;
          nixpkgs.config = config.nixpkgs.config;
        }
      ];
      specialArgs = lib.ghaf.vm.mkSpecialArgs {
        inherit lib inputs;
        globalConfig = hostGlobalConfig;
        hostConfig =
          lib.ghaf.vm.mkHostConfig {
            inherit config;
            vmName = "audio-vm";
          }
          // {
            # Audio-specific hostConfig fields
            audiovm = {
              audio = config.ghaf.virtualization.microvm.audiovm.audio or false;
            };
          };
      };
    };

    # Export Net VM base for profiles to extend
    ghaf.profiles.laptop-x86.netvmBase = lib.nixosSystem {
      inherit (inputs.nixpkgs.legacyPackages.x86_64-linux) system;
      modules = [
        inputs.microvm.nixosModules.microvm
        inputs.self.nixosModules.netvm-base
        # Import nixpkgs config module to get overlays
        {
          nixpkgs.overlays = config.nixpkgs.overlays;
          nixpkgs.config = config.nixpkgs.config;
        }
      ];
      specialArgs = lib.ghaf.vm.mkSpecialArgs {
        inherit lib inputs;
        globalConfig = hostGlobalConfig;
        hostConfig =
          lib.ghaf.vm.mkHostConfig {
            inherit config;
            vmName = "net-vm";
          }
          // {
            # Net-specific hostConfig fields
            netvm = {
              wifi = config.ghaf.virtualization.microvm.netvm.wifi or false;
            };
          };
      };
    };

    # Export mkAppVm function for creating App VMs
    # Unlike singleton VMs, App VMs are instantiated multiple times
    ghaf.profiles.laptop-x86.mkAppVm =
      vmDef:
      lib.nixosSystem {
        inherit (inputs.nixpkgs.legacyPackages.x86_64-linux) system;
        modules = [
          inputs.microvm.nixosModules.microvm
          inputs.self.nixosModules.appvm-base
          # Import nixpkgs config module to get overlays
          {
            nixpkgs.overlays = config.nixpkgs.overlays;
            nixpkgs.config = config.nixpkgs.config;
          }
        ];
        specialArgs = lib.ghaf.vm.mkSpecialArgs {
          inherit lib inputs;
          globalConfig = hostGlobalConfig;
          hostConfig =
            lib.ghaf.vm.mkHostConfig {
              inherit config;
              vmName = "${vmDef.name}-vm";
            }
            // {
              # App VM-specific hostConfig fields
              appvm = vmDef;
              # Pass shared directory config for storage
              sharedVmDirectory =
                config.ghaf.virtualization.microvm-host.sharedVmDirectory or {
                  enable = false;
                  vms = [ ];
                };
            };
        };
      };

    ghaf = {
      # Hardware definitions
      hardware = {
        x86_64.common.enable = true;
        tpm2.enable = true;
        passthrough = {
          vhotplug.enable = true;
          usbQuirks.enable = true;

        };
      };

      # Virtualization options
      virtualization = {
        microvm-host = {
          enable = true;
          networkSupport = true;
          sharedVmDirectory = {
            enable = true;
          };
        };

        microvm = {
          netvm = {
            enable = true;
            wifi = true;
            # evaluatedConfig is set by profile (e.g., mvp-user-trial.nix)
          };

          adminvm = {
            enable = true;
            # evaluatedConfig is set by profile (e.g., mvp-user-trial.nix)
          };

          idsvm = {
            enable = false;
            mitmproxy.enable = false;
          };

          guivm = {
            enable = true;
            # evaluatedConfig is set by profile (e.g., mvp-user-trial.nix)
            # Profile extends guivmBase and collects extraModules
          };

          audiovm = {
            enable = true;
            audio = true;
          };
        };
      };

      # Enable givc
      givc.enable = true;
      givc.debug = false;

      host = {
        networking.enable = true;
      };
    };
  };
}
