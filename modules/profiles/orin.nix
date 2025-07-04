# Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{ config, lib, ... }:
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
        renderer = "gles2";
        compositor = "labwc";
        idleManagement.enable = false;
        # Disable suspend by default, not working as intended
        allowSuspend = false;
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
          # sharedVmDirectory = {
          #   enable = true;
          # };
        };

        microvm = {
          netvm = {
            enable = true;
            #wifi = true;
            extraModules = cfg.netvmExtraModules;
          };

          adminvm = {
            enable = false;
          };

          gpuvm = {
            enable = true;
          };
        };

        #nvidia-podman.daemon.enable = true;
        nvidia-docker.daemon.enable = true;
      };

      # Disable givc
      givc.enable = false;

      host = {
        networking.enable = true;
      };

      # Create admin home folder; temporary solution
      users.admin.createHome = true;
    };
  };
}
