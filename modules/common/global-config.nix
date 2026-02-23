# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# Global Configuration Options Module
#
# This module defines the ghaf.global-config option type for host-level settings.
# The actual global config values are created by lib.ghaf.mkGlobalConfig and
# passed to VMs via specialArgs (globalConfig).
#
# Usage:
#   # Set options on host (these propagate via lib.ghaf.mkGlobalConfig)
#   ghaf.profiles.debug.enable = true;
#   ghaf.development.ssh.daemon.enable = true;
#
#   # VMs receive globalConfig via specialArgs, created by profiles
#   # See: modules/profiles/laptop-x86.nix, lib/global-config.nix
#
{
  config,
  lib,
  ...
}:
{
  _file = ./global-config.nix;

  options.ghaf.global-config = lib.mkOption {
    type = lib.types.globalConfig;
    default = { };
    description = "Global configuration options that propagate to all VMs via specialArgs.";
  };

  config = {
    ghaf.global-config = {
      # Populate platform information from host config
      platform = {
        buildSystem = lib.mkDefault config.nixpkgs.buildPlatform.system;
        hostSystem = lib.mkDefault config.nixpkgs.hostPlatform.system;
        timeZone = lib.mkDefault config.time.timeZone;
      };

      # Propagate host storeOnDisk setting to global-config for VMs
      storage.storeOnDisk = lib.mkIf config.ghaf.virtualization.microvm.storeOnDisk true;

      # Auto-populate logging listener address from admin-vm IP
      # The logging listener always runs on admin-vm, so derive the address
      # from hosts.nix rather than requiring each profile to set it manually.
      logging.listener.address = lib.mkIf (
        config.ghaf.global-config.logging.enable && config.ghaf.common.adminHost != null
      ) (lib.mkDefault config.ghaf.networking.hosts.admin-vm.ipv4);
    };
  };
}
