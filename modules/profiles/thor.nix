# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# NVIDIA Jetson Thor Profile
#
# This profile configures Ghaf for NVIDIA Jetson Thor hardware (AGX).
#
# VM Configuration on Jetson:
# ===========================
# Enabled VMs:
# - Admin VM (adminvmBase exported for composition)
#
{
  config,
  lib,
  pkgs,
  inputs,
  ...
}:
let
  cfg = config.ghaf.profiles.thor;
  hostGlobalConfig = config.ghaf.global-config;
in
{
  _file = ./thor.nix;

  options.ghaf.profiles.thor = {
    enable = lib.mkEnableOption "Enable the basic nvidia orin thor config";

    adminvmBase = lib.mkOption {
      type = lib.types.unspecified;
      readOnly = true;
      description = ''
        Admin VM base configuration. Profiles can extend this with extendModules if customization needed.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    ghaf = {
      hardware.definition.type = "embedded";

      profiles = {
        thor.adminvmBase = lib.nixosSystem {
          modules = [
            inputs.microvm.nixosModules.microvm
            inputs.self.nixosModules.adminvm-base
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
          # Enabled for testing
          enable = true;
          autoLogin = {
            enable = true;
            user = config.ghaf.users.admin.name;
          };
          bluetooth.applet.enable = false;
          networkManager.applet.enable = false;
        };
      };

      # Disable suspend by default, not working as intended
      services.power-manager.suspend.enable = false;

      graphics.cosmic = {
        renderDevice = "renderD129";
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
        idleManagement.enable = false;
      };

      reference.programs.windows-launcher.enable = false;
      reference.host-demo-apps.demo-apps.enableDemoApplications = false;

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
          adminvm = {
            enable = true;
            evaluatedConfig = cfg.adminvmBase;
          };

          idsvm = {
            enable = false;
          };

          guivm = {
            enable = false;
          };

          audiovm = {
            enable = false;
          };
        };

        nvidia-docker.daemon.enable = true;
      };

      # Enable when fixes ready
      givc.enable = false;
      global-config.givc.enable = false;

      host.networking.enable = true;
      users.admin.enableUILogin = true;
    };

    hardware.graphics.extraPackages = lib.mkAfter [
      pkgs.mesa
    ];
  };
}
