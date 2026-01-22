# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.ghaf.profiles.orin;
in
{
  options.ghaf.profiles.orin = {
    enable = lib.mkEnableOption "Enable the basic nvidia orin config";

    netvmExtraModules = lib.mkOption {
      description = ''
        List of additional modules to be passed to the netvm.
      '';
      default = [ ];
    };

  };

  config = lib.mkIf cfg.enable {
    ghaf = {
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
            extraModules = cfg.netvmExtraModules;
          };

          adminvm = {
            enable = true;
            extraModules = [
              {
                config.ghaf = {
                  inherit (config.ghaf) common;
                };
              }
            ];
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
