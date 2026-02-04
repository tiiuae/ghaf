# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# Profile for VM targets that run GUI on the host (no gui-vm microvm).
# This profile creates VM bases for: netvm, audiovm, adminvm
# but NOT guivm (since GUI runs on host).
#
{
  config,
  lib,
  inputs,
  ...
}:
let
  cfg = config.ghaf.profiles.vm;
  hostGlobalConfig = config.ghaf.global-config;
in
{
  _file = ./vm.nix;

  options.ghaf.profiles.vm = {
    enable = lib.mkEnableOption "VM target profile (GUI runs on host, no gui-vm)";

    # Net VM base configuration
    netvmBase = lib.mkOption {
      type = lib.types.unspecified;
      readOnly = true;
      description = ''
        VM profile Net VM base configuration.
        Use extendModules to add hardware passthrough and GIVC overrides.
      '';
    };

    # Audio VM base configuration
    audiovmBase = lib.mkOption {
      type = lib.types.unspecified;
      readOnly = true;
      description = ''
        VM profile Audio VM base configuration.
        Use extendModules to add GIVC socket proxy configuration.
      '';
    };

    # Admin VM base configuration
    adminvmBase = lib.mkOption {
      type = lib.types.unspecified;
      readOnly = true;
      description = ''
        VM profile Admin VM base configuration.
      '';
    };

    # App VM factory function
    mkAppVm = lib.mkOption {
      type = lib.types.unspecified;
      readOnly = true;
      description = ''
        Function to create App VM configurations.
        Takes a vmDef attribute set and returns a NixOS configuration.
        The result can be extended with:
          (mkAppVm vmDef).extendModules { modules = [ ... ]; }
      '';
    };
  };

  config = lib.mkIf cfg.enable {

    # Export Net VM base
    ghaf.profiles.vm.netvmBase = lib.nixosSystem {
      inherit (inputs.nixpkgs.legacyPackages.x86_64-linux) system;
      modules = [
        inputs.microvm.nixosModules.microvm
        inputs.self.nixosModules.netvm-base
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
            netvm = {
              wifi = config.ghaf.virtualization.microvm.netvm.wifi or false;
            };
          };
      };
    };

    # Export Audio VM base
    ghaf.profiles.vm.audiovmBase = lib.nixosSystem {
      inherit (inputs.nixpkgs.legacyPackages.x86_64-linux) system;
      modules = [
        inputs.microvm.nixosModules.microvm
        inputs.self.nixosModules.audiovm-base
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
            audiovm = {
              audio = config.ghaf.virtualization.microvm.audiovm.audio or false;
            };
          };
      };
    };

    # Export Admin VM base
    ghaf.profiles.vm.adminvmBase = lib.nixosSystem {
      inherit (inputs.nixpkgs.legacyPackages.x86_64-linux) system;
      modules = [
        inputs.microvm.nixosModules.microvm
        inputs.self.nixosModules.adminvm-base
        inputs.self.nixosModules.adminvm-features
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

    # Export mkAppVm function for creating App VMs
    ghaf.profiles.vm.mkAppVm =
      vmDef:
      lib.nixosSystem {
        inherit (inputs.nixpkgs.legacyPackages.x86_64-linux) system;
        modules = [
          inputs.microvm.nixosModules.microvm
          inputs.self.nixosModules.appvm-base
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
              appvm = vmDef;
              sharedVmDirectory =
                config.ghaf.virtualization.microvm-host.sharedVmDirectory or {
                  enable = false;
                  vms = [ ];
                };
            };
        };
      };
  };
}
