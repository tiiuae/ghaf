# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  config,
  lib,
  inputs,
  ...
}:
let
  cfg = config.ghaf.reference.profiles.mvp-user-trial;
  hostGlobalConfig = config.ghaf.global-config;
in
{
  options.ghaf.reference.profiles.mvp-user-trial = {
    enable = lib.mkEnableOption "Enable the mvp configuration for apps and services";
  };

  config = lib.mkIf cfg.enable {
    ghaf = {

      # Setup user profiles
      users.profile = {
        homed-user.enable = true;
        ad-users.enable = false;
        mutable-users.enable = false;
      };

      # Enable shared directories for the selected VMs
      virtualization.microvm-host.sharedVmDirectory.vms = [
        "business-vm"
        "comms-vm"
        "chrome-vm"
        "flatpak-vm"
      ];

      virtualization.microvm.appvm = {
        enable = true;
        vms = {
          business.enable = true;
          chrome.enable = true;
          comms.enable = true;
          flatpak.enable = true;
          gala.enable = false;
          zathura.enable = true;
        };
      };

      hardware.passthrough = {
        mode = "dynamic";
        VMs = {
          gui-vm.permittedDevices = [
            "crazyradio0"
            "crazyradio1"
            "crazyfile0"
            "fpr0"
            "usbKBD"
            "xbox0"
            "xbox1"
            "xbox2"
          ];
          comms-vm.permittedDevices = [ "gps0" ];
          audio-vm.permittedDevices = [ "bt0" ];
          business-vm.permittedDevices = [ "cam0" ];
        };
        usb = {
          guivmRules = lib.mkOptionDefault [
            {
              description = "Fingerprint Readers for GUIVM";
              targetVm = "gui-vm";
              allow = config.ghaf.reference.passthrough.usb.fingerprintReaders;
            }
          ];
        };
      };

      reference = {
        appvms.enable = true;
        services = {
          enable = true;
          dendrite = false;
          proxy-business = lib.mkForce config.ghaf.virtualization.microvm.appvm.vms.business.enable;
          google-chromecast = {
            enable = true;
            # Should match the name of the chrome VM above
            vmName = "chrome-vm";
          };
          alpaca-ollama = true;
          wireguard-gui = true;
        };

        personalize = {
          keys.enable = true;
        };

        desktop.applications.enable = true;
        desktop.ghaf-intro.enable = true;
      };

      profiles = {
        laptop-x86 = {
          enable = true;
          netvmExtraModules = [
            ../services
            ../personalize
            { ghaf.reference.personalize.keys.enable = true; }
          ];
          # guivmExtraModules removed - now using evaluatedConfig below
        };
      };

      # GUI VM: Extend laptop base with MVP services (HYBRID: includes extraModules)
      virtualization.microvm.guivm.evaluatedConfig =
        config.ghaf.profiles.laptop-x86.guivmBase.extendModules
          {
            modules = [
              ../services
              ../programs
              ../personalize
              { ghaf.reference.personalize.keys.enable = true; }
            ]
            ++ config.ghaf.virtualization.microvm.guivm.extraModules;
            specialArgs = lib.ghaf.mkVmSpecialArgs {
              inherit lib inputs;
              globalConfig = hostGlobalConfig;
              hostConfig = lib.ghaf.mkVmHostConfig {
                inherit config;
                vmName = "gui-vm";
              };
            };
          };

      # Enable logging
      logging = {
        enable = true;
        server.endpoint = "https://loki.ghaflogs.vedenemo.dev/loki/api/v1/push";
        listener.address = config.ghaf.networking.hosts.admin-vm.ipv4;
      };

      # Disk encryption - deferred to first boot
      storage.encryption = {
        enable = true;
        deferred = true;
      };

      # Enable audit
      security.audit.enable = false;

      # Enable power management
      services.power-manager.enable = true;

      # Enable performance optimizations
      services.performance.enable = true;

      # Enable kill switch
      services.kill-switch.enable = true;
    };
  };
}
