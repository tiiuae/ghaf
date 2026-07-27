# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  config,
  lib,
  inputs,
  ...
}:
let
  cfg = config.ghaf.reference.profiles.mvp-orinuser-trial;
  hostGlobalConfig = config.ghaf.global-config;
in
{
  _file = ./mvp-orinuser-trial.nix;

  options.ghaf.reference.profiles.mvp-orinuser-trial = {
    enable = lib.mkEnableOption "the mvp configuration for apps and services";
  };

  config = lib.mkIf cfg.enable {
    ghaf = {
      virtualization = {
        # Enable shared directories for the selected VMs
        microvm-host.sharedVmDirectory.vms = [
          "net-vm"
        ];

        microvm.appvm = {
          enable = true;
          vms = {
          };
        };

        # GUI VM: extend the Orin base with the MVP desktop bundle, mirroring
        # the x86 pattern in mvp-user-trial.nix. Overrides the hardware-only
        # mkDefault evaluatedConfig from profiles/orin.nix.
        microvm.guivm.evaluatedConfig = config.ghaf.profiles.orin.guivmBase.extendModules {
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

        # Net VM profile-specific modules - use vmConfig for resource allocation and profile services
        # Hardware-specific modules should go in hardware.definition.netvm.extraModules
        vmConfig.sysvms.netvm.extraModules = [
          ../services
          ../personalize
          # Developer SSH access is a DEBUG-build affordance: this option's
          # default is the ghaf developer key list
          # (../personalize/authorizedSshKeys.nix), and enabling it grants every
          # one of those keys a shell as root and as the admin user.
          { ghaf.reference.personalize.keys.enable = config.ghaf.profiles.debug.enable; }
          # Forward host reference services config to netvm
          {
            ghaf.reference.services = {
              inherit (config.ghaf.reference.services) enable dendrite;
            };
          }
        ];
      };

      reference = {
        appvms.enable = true;
        # One App VM for the accelerated gui-vm bring-up: gala is the smallest
        # reference App VM and ships an arm64 build. Its window reaches the
        # gui-vm COSMIC session via the standard Waypipe/vsock path.
        appvms.gala.enable = true;

        services = {
          enable = true;
          dendrite = false;
        };

        personalize = {
          # Debug-only; see the net-vm block above.
          keys.enable = config.ghaf.profiles.debug.enable;
        };

        desktop.applications.enable = false;
      };

      profiles.orin.enable = true;

      graphics = {
        # Plymouth doesn't work as it should on Orins
        boot.enable = lib.mkForce false;
      };

      host.networking = {
        enable = lib.mkForce true;
      };

      security.audit.enable = false;

      # osquery fails to build for cross-compiled targets
      services.orbit.enable = lib.mkForce false;
    };
  };
}
