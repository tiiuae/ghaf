# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  config,
  lib,
  ...
}:
let
  cfg = config.ghaf.reference.profiles.mvp-user-trial;
in
{
  _file = ./mvp-user-trial.nix;

  options.ghaf.reference.profiles.mvp-user-trial = {
    enable = lib.mkEnableOption "the mvp configuration for apps and services";
  };

  config = lib.mkIf cfg.enable {
    ghaf = {

      # Setup user profiles
      users.profile = {
        homed-user.enable = true;
        ad-users.enable = false;
        mutable-users.enable = false;
      };

      virtualization = {
        # Enable shared directories for the selected VMs
        microvm-host.sharedVmDirectory.vms = [
          "business-vm"
          "comms-vm"
          "chrome-vm"
          "flatpak-vm"
        ];

        microvm = {
          appvm = {
            enable = true;
            vms = {
              business.enable = true;
              chrome.enable = true;
              comms.enable = true;
              flatpak.enable = true;
              gala.enable = false;
              media.enable = true;
            };
          };
        };

        # System-VM policy.
        #
        # The COMPOSITION of the system VMs -- turning each *Base option into an
        # evaluatedConfig and threading applyVmConfig -- now lives in
        # modules/profiles/laptop-x86.nix, which binds all four under
        # lib.mkDefault. This profile supplies only what makes it the Ghaf
        # reference product, and it does so through
        # ghaf.virtualization.vmConfig.sysvms.<vm>.extraModules: the same
        # declared option a downstream project uses.
        #
        # It also means this file no longer calls lib.ghaf.vm.applyVmConfig,
        # mkSpecialArgs or mkHostConfig -- it has no dependency on ghaf
        # internals.
        vmConfig.sysvms = {
          guivm.extraModules = [
            # Reference services and personalization
            ../services
            ../programs
            ../personalize
            {
              # Developer SSH access is a DEBUG-build affordance.
              #
              # This option's default is the ghaf developer key list
              # (../personalize/authorizedSshKeys.nix), and enabling it grants
              # every one of those keys a shell as root and as the admin user.
              # Enabling it unconditionally put them on release images too.
              #
              # Same gate as targets/imx8mp-evk/flake-module.nix and
              # ../hardware/jetpack/profiles/debug.nix already use.
              ghaf.reference.personalize.keys.enable = config.ghaf.profiles.debug.enable;
              # Forward host reference services config to guivm
              ghaf.reference.services = {
                inherit (config.ghaf.reference.services)
                  enable
                  wireguard-gui
                  ;
              };
            }
          ];

          netvm.extraModules = [
            # Reference services and personalization
            ../services
            ../personalize
            # Forward host reference services config to netvm
            {
              ghaf.reference = {
                # Debug-only; see the gui-vm block above.
                personalize.keys.enable = config.ghaf.profiles.debug.enable;
                services = {
                  inherit (config.ghaf.reference.services)
                    enable
                    dendrite
                    proxy-business
                    ;
                  google-chromecast = {
                    inherit (config.ghaf.reference.services.google-chromecast) enable vmName;
                  };
                  chromecast = {
                    inherit (config.ghaf.reference.services.chromecast) externalNic internalNic;
                  };
                };
              };
            }
          ];
        };
      };

      hardware.passthrough = {
        mode = "dynamic";

        VMs = {
          # Device names are defined in reference hardware modules (e.g., x1-gen11.nix)
          gui-vm.permittedDevices = [
            "crazyradio0" # Bitcraze Crazyradio PA
            "crazyradio1"
            "crazyfile0" # Bitcraze Crazyradio file interface
            "fpr0" # Fingerprint reader
            "usbKBD" # External USB keyboard
            "xbox0" # Xbox controller
            "xbox1"
            "xbox2"
          ];
          comms-vm.permittedDevices = [ "gps0" ]; # GPS dongle
          audio-vm.permittedDevices = [ "bt0" ]; # Bluetooth adapter
          business-vm.permittedDevices = [ "cam0" ]; # Internal webcam
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
        appvms = {
          enable = true;
          business.enable = true;
          chrome.enable = true;
          comms.enable = true;
          flatpak.enable = true;
          media.enable = true;
        };

        services = {
          enable = true;
          dendrite = false;
          proxy-business = lib.mkForce config.ghaf.virtualization.microvm.appvm.vms.business.enable;
          google-chromecast = {
            enable = true;
            vmName = "chrome-vm";
          };
          wireguard-gui = true;
        };

        # Debug-only; see the gui-vm block above.
        personalize.keys.enable = config.ghaf.profiles.debug.enable;

        desktop.applications.enable = true;
        desktop.ghaf-intro.enable = true;
      };

      profiles.laptop-x86.enable = true;

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

      services = {
        # Enable kill switch
        kill-switch.enable = true;
      };
    };
  };
}
