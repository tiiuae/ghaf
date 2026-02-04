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
    description = ''
      Global configuration options that propagate to all VMs.

      These settings represent the "single source of truth" for values that
      should be consistent across the host and all guest virtual machines.

      The actual propagation to VMs happens via:
      1. lib.ghaf.mkGlobalConfig creates globalConfig from host config
      2. Profiles pass globalConfig to VM bases via specialArgs
      3. VMs read from globalConfig specialArg

      Hardware-specific VM configurations go via hardware definition:
        ghaf.hardware.definition.guivm.extraModules = [{
          # Hardware-specific overrides for GUI VM
          microvm.mem = 8192;
        }];
    '';
  };

  config = {
    # Populate platform information from host config
    ghaf.global-config.platform = {
      buildSystem = lib.mkDefault config.nixpkgs.buildPlatform.system;
      hostSystem = lib.mkDefault config.nixpkgs.hostPlatform.system;
      timeZone = lib.mkDefault (if config.time.timeZone != null then config.time.timeZone else "UTC");
    };
  };
}
