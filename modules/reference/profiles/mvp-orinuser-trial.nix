# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  config,
  lib,
  ...
}:
let
  cfg = config.ghaf.reference.profiles.mvp-orinuser-trial;
in
{
  options.ghaf.reference.profiles.mvp-orinuser-trial = {
    enable = lib.mkEnableOption "Enable the mvp configuration for apps and services";
  };

  config = lib.mkIf cfg.enable {
    ghaf = {
      # Enable shared directories for the selected VMs
      virtualization.microvm-host.sharedVmDirectory.vms = [
        "net-vm"
      ];

      virtualization.microvm.appvm = {
        enable = true;
        vms = {
        };
      };

      reference = {
        appvms.enable = true;

        services = {
          enable = true;
          dendrite = false;
        };

        personalize = {
          keys.enable = true;
        };

        desktop.applications.enable = false;
      };

      profiles = {
        orin = {
          enable = true;
          netvmExtensions = [
            ../services
            ../personalize
            { ghaf.reference.personalize.keys.enable = true; }
          ];
        };
      };

      graphics = {
        # Plymouth doesn't work as it should on Orins
        boot.enable = lib.mkForce false;
      };

      # Commented out sections below are used for
      #  network overriding tests. Just enable
      #  these lines to change vm and host ip addresses
      #  and bridge interface names.
      host.networking = {
        enable = lib.mkForce true;
        # bridgeNicName = lib.mkForce "fog-lan";
      };

      # common.extraNetworking.hosts = {
      #   net-vm = {
      #     ipv4 = lib.mkForce "10.10.10.1";
      #     mac = lib.mkForce "02:AD:00:00:00:FA";
      #     # interfaceName = lib.mkForce "new-nic";
      #   };
      #   admin-vm = {
      #     ipv4 = lib.mkForce "10.10.10.3";
      #     mac = lib.mkForce "02:AD:00:00:00:FB";
      #     #interfaceName = lib.mkForce "new-nic";
      #   };
      #   ghaf-host = {
      #     ipv4 = lib.mkForce "10.10.10.2";
      #     # interfaceName = lib.mkForce "foglan";
      #     # gives assertion error as expected
      #     # mac = lib.mkForce "DE:AD:BE:EF:00:02";
      #     # gives assertion error as expected
      #   };
      # };

      # Disable logging
      # logging = {
      #   enable = true;
      #   server.endpoint = "https://loki.ghaflogs.vedenemo.dev/loki/api/v1/push";
      #   listener.address = config.ghaf.networking.hosts.admin-vm.ipv4;
      # };

      # Enable audit
      security.audit.enable = false;
    };
  };
}
