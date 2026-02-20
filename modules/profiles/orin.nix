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
  _file = ./orin.nix;

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
      # Orin devices are embedded, not laptops
      hardware.definition.type = "embedded";

      profiles = {
        # Export Net VM base for profiles to extend
        orin.netvmBase = lib.nixosSystem {
          modules = [
            inputs.microvm.nixosModules.microvm
            inputs.self.nixosModules.netvm-base
            # Import nixpkgs config module to get overlays
            {
              nixpkgs = {
                hostPlatform.system = "aarch64-linux";
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

        # Export Admin VM base for profiles to extend
        orin.adminvmBase = lib.nixosSystem {
          modules = [
            inputs.microvm.nixosModules.microvm
            inputs.self.nixosModules.adminvm-base
            # Import nixpkgs config module to get overlays
            {
              nixpkgs = {
                hostPlatform.system = "aarch64-linux";
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

        graphics = {
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
      };

      # Disable suspend by default, not working as intended
      services.power-manager.suspend.enable = false;

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
            # wifi is now controlled via ghaf.global-config.features.wifi
            # Use evaluatedConfig pattern - extend netvmBase with vmConfig modules
            evaluatedConfig = config.ghaf.profiles.orin.netvmBase.extendModules {
              modules = lib.ghaf.vm.applyVmConfig {
                inherit config;
                vmName = "netvm";
              };
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
            # fprint/yubikey/brightness now controlled via ghaf.global-config.features
          };

          audiovm = {
            enable = false;
            # audio now controlled via ghaf.global-config.features.audio
          };
        };

        #nvidia-podman.daemon.enable = true;
        nvidia-docker.daemon.enable = true;
      };

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
