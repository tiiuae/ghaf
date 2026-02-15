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
  _file = ./laptop-x86.nix;

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
      description = "Function to create App VM configurations from a vmDef attribute set.";
    };
  };

  config = lib.mkIf cfg.enable {

    ghaf = {
      profiles.laptop-x86 = {
        # Export GUI VM base for profiles to extend
        guivmBase = lib.nixosSystem {
          modules = [
            inputs.microvm.nixosModules.microvm
            inputs.self.nixosModules.guivm-base
            inputs.self.nixosModules.guivm-features
            # Import nixpkgs config module to get overlays
            {
              nixpkgs = {
                hostPlatform.system = "x86_64-linux";
                inherit (config.nixpkgs) overlays;
                inherit (config.nixpkgs) config;
              };
            }
          ];
          specialArgs = lib.ghaf.vm.mkSpecialArgs {
            inherit lib inputs;
            globalConfig = hostGlobalConfig;
            hostConfig = lib.ghaf.vm.mkHostConfig {
              inherit config;
              vmName = "gui-vm";
            };
            # Note: guivm fprint/yubikey/brightness now controlled via globalConfig.features
          };
        };

        # Export Admin VM base for profiles to extend
        adminvmBase = lib.nixosSystem {
          modules = [
            inputs.microvm.nixosModules.microvm
            inputs.self.nixosModules.adminvm-base
            inputs.self.nixosModules.adminvm-features
            # Import nixpkgs config module to get overlays
            {
              nixpkgs = {
                hostPlatform.system = "x86_64-linux";
                inherit (config.nixpkgs) overlays;
                inherit (config.nixpkgs) config;
              };
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
        idsvmBase = lib.nixosSystem {
          modules = [
            inputs.microvm.nixosModules.microvm
            inputs.self.nixosModules.idsvm-base
            # Import nixpkgs config module to get overlays
            {
              nixpkgs = {
                hostPlatform.system = "x86_64-linux";
                inherit (config.nixpkgs) overlays;
                inherit (config.nixpkgs) config;
              };
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
        audiovmBase = lib.nixosSystem {
          modules = [
            inputs.microvm.nixosModules.microvm
            inputs.self.nixosModules.audiovm-base
            inputs.self.nixosModules.audiovm-features
            # Import nixpkgs config module to get overlays
            {
              nixpkgs = {
                hostPlatform.system = "x86_64-linux";
                inherit (config.nixpkgs) overlays;
                inherit (config.nixpkgs) config;
              };
            }
          ];
          specialArgs = lib.ghaf.vm.mkSpecialArgs {
            inherit lib inputs;
            globalConfig = hostGlobalConfig;
            hostConfig = lib.ghaf.vm.mkHostConfig {
              inherit config;
              vmName = "audio-vm";
            };
            # Note: audiovm.audio now controlled via globalConfig.features.audio
          };
        };

        # Export Net VM base for profiles to extend
        netvmBase = lib.nixosSystem {
          modules = [
            inputs.microvm.nixosModules.microvm
            inputs.self.nixosModules.netvm-base
            # Import nixpkgs config module to get overlays
            {
              nixpkgs = {
                hostPlatform.system = "x86_64-linux";
                inherit (config.nixpkgs) overlays;
                inherit (config.nixpkgs) config;
              };
            }
          ];
          specialArgs = lib.ghaf.vm.mkSpecialArgs {
            inherit lib inputs;
            globalConfig = hostGlobalConfig;
            hostConfig = lib.ghaf.vm.mkHostConfig {
              inherit config;
              vmName = "net-vm";
            };
            # Note: netvm.wifi now controlled via globalConfig.features.wifi
          };
        };

        # Export mkAppVm function for creating App VMs
        # Unlike singleton VMs, App VMs are instantiated multiple times
        #
        # Note: Extensions (e.g., from ghaf-intro) are now handled via the
        # `extensions` option in appvm.nix, applied via NixOS native extendModules.
        # mkAppVm no longer needs to read host-level options.
        mkAppVm =
          vmDef:
          let
            # Apply vmConfig.appvms overrides (ramMb, cores)
            vmCfg = config.ghaf.virtualization.vmConfig.appvms.${vmDef.name} or { };
            effectiveDef =
              vmDef
              // lib.optionalAttrs ((vmCfg.ramMb or null) != null) { inherit (vmCfg) ramMb; }
              // lib.optionalAttrs ((vmCfg.cores or null) != null) { inherit (vmCfg) cores; }
              // lib.optionalAttrs ((vmCfg.balloonRatio or null) != null) { inherit (vmCfg) balloonRatio; };
          in
          lib.nixosSystem {
            modules = [
              inputs.microvm.nixosModules.microvm
              inputs.self.nixosModules.appvm-base
              # Import nixpkgs config module to get overlays
              {
                nixpkgs = {
                  hostPlatform.system = "x86_64-linux";
                  inherit (config.nixpkgs) overlays;
                  inherit (config.nixpkgs) config;
                };
              }
            ]
            ++ (vmCfg.extraModules or [ ]);
            specialArgs = lib.ghaf.vm.mkSpecialArgs {
              inherit lib inputs;
              globalConfig = hostGlobalConfig;
              hostConfig =
                lib.ghaf.vm.mkHostConfig {
                  inherit config;
                  vmName = "${effectiveDef.name}-vm";
                }
                // {
                  # App VM-specific hostConfig fields
                  appvm = effectiveDef;
                  # Pass shared directory config for storage
                  sharedVmDirectory =
                    config.ghaf.virtualization.microvm-host.sharedVmDirectory or {
                      enable = false;
                      vms = [ ];
                    };
                };
            };
          };
      };
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
            # wifi is now controlled via ghaf.global-config.features.wifi
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
            # fprint/yubikey/brightness now controlled via ghaf.global-config.features
            # evaluatedConfig is set by profile (e.g., mvp-user-trial.nix)
            # Profile extends guivmBase and collects extraModules
          };

          audiovm = {
            enable = true;
            # audio is now controlled via ghaf.global-config.features.audio
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
