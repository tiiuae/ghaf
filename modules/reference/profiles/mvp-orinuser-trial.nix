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

        # Net VM profile-specific modules - use vmConfig for resource allocation and profile services
        # Hardware-specific modules should go in hardware.definition.netvm.extraModules
        vmConfig.sysvms.netvm.extraModules = [
          ../services
          ../personalize
          (
            { globalConfig, ... }:
            {
              # Dev-team SSH keys are a debug convenience; this trial profile
              # is also used for release variants.
              ghaf.reference.personalize.keys.enable = globalConfig.debug.enable or false;
            }
          )
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

        services = {
          enable = true;
          dendrite = false;
        };

        personalize = {
          keys.enable = true;
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
