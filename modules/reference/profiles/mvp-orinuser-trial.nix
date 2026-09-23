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
  acceleratedGuiVm = config.ghaf.hardware.nvidia.passthroughs.gui_vm.enable;
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
          enable = acceleratedGuiVm;
          vms = {
          };
        };

        microvm.guivm.evaluatedConfig = config.ghaf.profiles.orin.guivmBase.extendModules {
          modules = [
            ../services
            ../programs
            {
              ghaf.reference.services = {
                inherit (config.ghaf.reference.services)
                  enable
                  wireguard-gui
                  ;
              };
            }
            inputs.self.nixosModules.guivm-desktop-features
          ]
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
          # Forward host reference services config to netvm
          {
            ghaf.reference.services = {
              inherit (config.ghaf.reference.services) enable dendrite;
            };
          }
        ];
      };

      reference = {
        appvms.enable = acceleratedGuiVm;
        appvms.chromium.enable = acceleratedGuiVm;
        appvms.flatpak.enable = acceleratedGuiVm;

        services = {
          enable = true;
          dendrite = false;
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

      security.audit.enable = true;

      # osquery fails to build for cross-compiled targets
      services.orbit.enable = lib.mkForce false;
    };
  };
}
