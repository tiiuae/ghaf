# Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{ config, lib, ... }:
{
  imports = [
    ../appvms
    ../programs
    ../services
    ../personalize
    ../desktop
  ];

  config = {
    ghaf = {
      # Enable disk partitioning
      partitioning.disko.enable = true;

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

      virtualization.microvm.appvm = {
        enable = true;
        vms = {
          chrome.enable = true;
          gala.enable = true;
          zathura.enable = true;
          comms.enable = true;
          business.enable = true;
        };
      };

      reference = {
        appvms.enable = true;

        services = {
          enable = true;
          dendrite = true;
          proxy-business = lib.mkForce config.ghaf.virtualization.microvm.appvm.vms.business.enable;
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
            ../services
            ../programs
            ../personalize
            {
              ghaf.reference.personalize.keys.enable = true;
              ghaf.reference.services.ollama = true;
            }
          ];
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
