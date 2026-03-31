# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  config,
  lib,
  inputs,
  sharedVms ? null,
  ...
}:
let
  cfg = config.ghaf.reference.profiles.mvp-user-trial;
  hostGlobalConfig = config.ghaf.global-config;
  hasShared = sharedVms != null;
in
{
  _file = ./mvp-user-trial.nix;

  options.ghaf.reference.profiles.mvp-user-trial = {
    enable = lib.mkEnableOption "Enable the mvp configuration for apps and services";
  };

  config = lib.mkMerge [
    {
      # Provide default for sharedVms when not passed via specialArgs.
      # The ? null default in the function signature does not work for NixOS
      # module arguments because the module system resolves them via
      # _module.args, bypassing the default.
      _module.args.sharedVms = lib.mkDefault null;
    }
    (lib.mkIf cfg.enable {
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
                zathura.enable = true;
              }
              # When shared VMs are available, override AppVM evaluatedConfigs
              # but skip any AppVM that has per-target vmConfig overrides
              // lib.optionalAttrs (hasShared && sharedVms ? appvm) (
                let
                  targetAppvmOverrides = config.ghaf.virtualization.vmConfig.appvms;
                  shareable = lib.filterAttrs (name: _: !(targetAppvmOverrides ? ${name})) sharedVms.appvm;
                in
                lib.mapAttrs (_name: eval: { evaluatedConfig = lib.mkForce eval; }) shareable
              );
            };

            # GUI VM: Extend laptop base with MVP services and feature modules
            guivm.evaluatedConfig = config.ghaf.profiles.laptop-x86.guivmBase.extendModules {
              modules = [
                # Reference services and personalization
                ../services
                ../programs
                ../personalize
                {
                  ghaf.reference.personalize.keys.enable = true;
                  # Forward host reference services config to guivm
                  ghaf.reference.services = {
                    inherit (config.ghaf.reference.services)
                      enable
                      alpaca-ollama
                      wireguard-gui
                      ;
                  };
                }
                # Feature modules (auto-include based on feature flags)
                inputs.self.nixosModules.guivm-desktop-features
              ]
              # Apply vmConfig (resource allocation + hardware + profile modules)
              ++ lib.ghaf.vm.applyVmConfig {
                inherit config;
                vmName = "guivm";
              };
              specialArgs = lib.ghaf.vm.mkSpecialArgs {
                inherit lib inputs;
                globalConfig = hostGlobalConfig;
                hostConfig = lib.ghaf.vm.mkHostConfig {
                  inherit config;
                  vmName = "gui-vm";
                };
              };
            };

            # Admin VM: Use shared pre-evaluated VM if available, otherwise create from laptop base
            adminvm.evaluatedConfig =
              if hasShared && sharedVms ? sysvm && sharedVms.sysvm ? adminvm then
                sharedVms.sysvm.adminvm
              else
                config.ghaf.profiles.laptop-x86.adminvmBase;

            # Audio VM: Use shared pre-evaluated VM if available, otherwise create from laptop base
            audiovm.evaluatedConfig =
              if hasShared && sharedVms ? sysvm && sharedVms.sysvm ? audiovm then
                sharedVms.sysvm.audiovm
              else
                config.ghaf.profiles.laptop-x86.audiovmBase.extendModules {
                  modules = lib.ghaf.vm.applyVmConfig {
                    inherit config;
                    vmName = "audiovm";
                  };
                };

            # Net VM: Use shared pre-evaluated VM if available, otherwise create from laptop base
            netvm.evaluatedConfig =
              if hasShared && sharedVms ? sysvm && sharedVms.sysvm ? netvm then
                sharedVms.sysvm.netvm
              else
                config.ghaf.profiles.laptop-x86.netvmBase.extendModules {
                  modules = [
                    # Reference services and personalization
                    ../services
                    ../personalize
                    # Forward host reference services config to netvm
                    {
                      ghaf.reference = {
                        personalize.keys.enable = true;
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
                  ]
                  ++ lib.ghaf.vm.applyVmConfig {
                    inherit config;
                    vmName = "netvm";
                  };
                };
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
            zathura.enable = true;
          };

          services = {
            enable = true;
            dendrite = false;
            proxy-business = lib.mkForce config.ghaf.virtualization.microvm.appvm.vms.business.enable;
            google-chromecast = {
              enable = true;
              vmName = "chrome-vm";
            };
            alpaca-ollama = true;
            wireguard-gui = true;
          };

          personalize.keys.enable = true;

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
          # Enable power management
          power-manager.enable = true;

          # Enable performance optimizations
          performance.enable = true;

          # Enable kill switch
          kill-switch.enable = true;
        };
      };
    })
  ];
}
