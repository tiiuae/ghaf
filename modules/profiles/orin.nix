# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# NVIDIA Jetson Orin Profile
#
# This profile configures Ghaf for NVIDIA Jetson Orin hardware (AGX, NX).
#
# VM Configuration on Jetson:
# ===========================
# Enabled VMs:
# - Net VM (netvmBase exported for composition)
# - Admin VM (adminvmBase exported for composition)
#
# Disabled VMs (architectural reasons):
# - GUI VM: GPU passthrough not supported, desktop runs natively on host (COSMIC)
# - Audio VM: Audio hardware directly accessible from host
# - IDS VM: Resource constraints on embedded platform
# - App VMs: No GUI VM means no Waypipe, apps run on host or via Docker
#
# Both netvmBase and adminvmBase are exported for composition needs.
#
{
  config,
  lib,
  pkgs,
  inputs,
  ...
}:
let
  cfg = config.ghaf.profiles.orin;
  hostGlobalConfig = config.ghaf.global-config;
in
{
  options.ghaf.profiles.orin = {
    enable = lib.mkEnableOption "Enable the basic nvidia orin config";

    # Net VM base configuration for profiles to extend
    netvmBase = lib.mkOption {
      type = lib.types.unspecified;
      readOnly = true;
      description = ''
        Orin Net VM base configuration.
        Profiles can extend this with extendModules if customization needed.
      '';
    };

    # Admin VM base configuration for profiles to extend
    adminvmBase = lib.mkOption {
      type = lib.types.unspecified;
      readOnly = true;
      description = ''
        Orin Admin VM base configuration.
        Profiles can extend this with extendModules if customization needed.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    ghaf = {
      # Export Net VM base for profiles to extend
      profiles.orin.netvmBase = lib.nixosSystem {
        system = "aarch64-linux";
        modules = [
          inputs.microvm.nixosModules.microvm
          inputs.self.nixosModules.netvm-base
          # Import nixpkgs config module to get overlays
          {
            nixpkgs.overlays = config.nixpkgs.overlays;
            nixpkgs.config = config.nixpkgs.config;
          }
        ];
        specialArgs = lib.ghaf.mkVmSpecialArgs {
          inherit lib inputs;
          globalConfig = hostGlobalConfig;
          hostConfig =
            lib.ghaf.mkVmHostConfig {
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

      # Export Admin VM base for profiles to extend
      profiles.orin.adminvmBase = lib.nixosSystem {
        system = "aarch64-linux";
        modules = [
          inputs.microvm.nixosModules.microvm
          inputs.self.nixosModules.adminvm-base
          # Import nixpkgs config module to get overlays
          {
            nixpkgs.overlays = config.nixpkgs.overlays;
            nixpkgs.config = config.nixpkgs.config;
          }
        ];
        specialArgs = lib.ghaf.mkVmSpecialArgs {
          inherit lib inputs;
          globalConfig = hostGlobalConfig;
          hostConfig = lib.ghaf.mkVmHostConfig {
            inherit config;
            vmName = "admin-vm";
          };
        };
      };

      profiles.graphics = {
        enable = true;
        # Explicitly enable auto-login for Orins
        autoLogin = {
          enable = true;
          user = config.ghaf.users.admin.name;
        };
        # We might be able to enable bluetooth and networkManager
        # together with applets without dbusProxy on Orins
        bluetooth.applet.enable = false;
        networkManager.applet.enable = false;
      };

      # Disable suspend by default, not working as intended
      services.power-manager.allowSuspend = false;

      graphics.cosmic = {
        # Crucial for Orin devices to use the correct render device
        # Also needs 'mesa' to be in hardware.graphics.extraPackages
        renderDevice = "/dev/dri/renderD129";
        # Keep only essential applets for Orin devices
        topPanelApplets.right = [
          "com.system76.CosmicAppletInputSources"
          "com.system76.CosmicAppletStatusArea"
          "com.system76.CosmicAppletTiling"
          "com.system76.CosmicAppletPower"
        ];
        bottomPanelApplets.right = [
          "com.system76.CosmicAppletInputSources"
          "com.system76.CosmicAppletStatusArea"
          "com.system76.CosmicAppletTiling"
          "com.system76.CosmicAppletPower"
        ];
        screenRecorder.enable = false;
      };

      reference.programs.windows-launcher.enable = true;
      reference.host-demo-apps.demo-apps.enableDemoApplications = true;

      hardware.nvidia = {
        virtualization.enable = true;
        virtualization.host.bpmp.enable = false;
        passthroughs.host.uarta.enable = false;
        # TODO: uarti passthrough is currently broken, it will be enabled
        # later after a further analysis.
        passthroughs.uarti_net_vm.enable = false;
      };

      # Virtualization options
      virtualization = {
        microvm-host = {
          enable = true;
          networkSupport = true;
          sharedVmDirectory = {
            enable = false;
          };
        };

        microvm = {
          netvm = {
            enable = true;
            wifi = false;
            # Use evaluatedConfig pattern - extend netvmBase with hardware-specific modules
            evaluatedConfig = config.ghaf.profiles.orin.netvmBase.extendModules {
              modules = config.ghaf.hardware.definition.netvm.extraModules or [ ];
            };
          };

          adminvm = {
            enable = true;
            # Use evaluatedConfig pattern - common is passed via hostConfig
            evaluatedConfig = cfg.adminvmBase;
          };

          idsvm = {
            enable = false;
          };

          guivm = {
            enable = false;
            #extraModules = cfg.guivmExtraModules;
          };

          audiovm = {
            enable = false;
            #audio = true;
          };
        };

        #nvidia-podman.daemon.enable = true;
        nvidia-docker.daemon.enable = true;
      };

      # Disable givc
      givc.enable = false;

      host.networking = {
        enable = true;
      };

      # Allow admin UI login
      users.admin.enableUILogin = true;
    };

    hardware.graphics.extraPackages = lib.mkAfter [
      pkgs.mesa
    ];
  };
}
