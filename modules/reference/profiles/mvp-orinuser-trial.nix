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
    enable = lib.mkEnableOption "Enable the mvp configuration for apps and services";
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
        vmConfig.netvm.extraModules = [
          ../services
          ../personalize
          { ghaf.reference.personalize.keys.enable = true; }
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
    };
  };
}
