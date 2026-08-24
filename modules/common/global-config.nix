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
#   ghaf.security.ssh.debug.enable = true;
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

      # Propagate host storeOnDisk setting to global-config for VMs. The
      # microvm module isn't imported by non-VM configs (e.g. installers),
      # so fall back to the submodule's own defaults (storeOnDisk disabled).
      storage.storeOnDisk = config.ghaf.virtualization.microvm.storeOnDisk or { };

      # Auto-populate logging listener address from admin-vm IP
      # The logging listener always runs on admin-vm, so derive the address
      # from hosts.nix rather than requiring each profile to set it manually.
      logging.listener.address = lib.mkIf (
        config.ghaf.global-config.logging.enable && config.ghaf.common.adminHost != null
      ) (lib.mkDefault config.ghaf.networking.hosts.admin-vm.ipv4);
      # Auto-populate logging TLS server_name for producer-side certificate validation.
      logging.listener.serverName = lib.mkIf (
        config.ghaf.global-config.logging.enable && config.ghaf.common.adminHost != null
      ) (lib.mkDefault "admin-vm");
    };
  };
}
