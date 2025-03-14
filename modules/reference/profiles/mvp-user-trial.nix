# Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{ config, lib, ... }:
let
  cfg = config.ghaf.reference.profiles.mvp-user-trial;
in
{
  imports = [
    ../appvms
    ../programs
    ../services
    ../personalize
    ../desktop
  ];

  options.ghaf.reference.profiles.mvp-user-trial = {
    enable = lib.mkEnableOption "Enable the mvp configuration for apps and services";
  };

  config = lib.mkIf cfg.enable {
    ghaf = {
      # Enable below option for session lock feature
      graphics = {
        #might be too optimistic to hide the boot logs
        #just yet :)
        # boot.enable = lib.mkForce true;
        labwc = {
          autolock.enable = lib.mkForce true;
          autologinUser = lib.mkForce null;
        };
      };

      # Enable shared directories for the selected VMs
      virtualization.microvm-host.sharedVmDirectory.vms = [
        "business-vm"
        "comms-vm"
        "chrome-vm"
      ];

      reference =
        let
          vms = {
            chrome-vm = true;
            gala-vm = true;
            zathura-vm = true;
            comms-vm = true;
            business-vm = true;
          };
        in
        {
          appvms =
            {
              enable = true;
            }
            // vms
            // {
              # Allow the above app VMs to access shared memory for GUI data handling
              shm-gui-enabled-vms = builtins.attrNames vms;
            }
            # Allow the above app VMs to access shared memory for audio data handling
            // {
              shm-audio-enabled-vms = builtins.attrNames vms;
            };

          services = {
            enable = true;
            dendrite = true;
            proxy-business = lib.mkForce config.ghaf.reference.appvms.business-vm;
            google-chromecast = true;
          };

          personalize = {
            keys.enable = true;
          };

          desktop.applications.enable = true;
        };

      profiles = {
        laptop-x86 = {
          enable = true;
          netvmExtraModules = [
            ../services
            ../personalize
            { ghaf.reference.personalize.keys.enable = true; }
          ];
          guivmExtraModules = [
            ../programs
            ../personalize
            { ghaf.reference.personalize.keys.enable = true; }
          ];
          inherit (config.ghaf.reference.appvms) enabled-app-vms;
        };
      };

      # Enable logging
      logging = {
        enable = true;
        server.endpoint = "https://loki.ghaflogs.vedenemo.dev/loki/api/v1/push";
        listener.address = config.ghaf.networking.hosts.admin-vm.ipv4;
      };
    };
  };
}
