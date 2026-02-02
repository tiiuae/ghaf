# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# Shared System Configuration Module
#
# This module defines configuration settings that should be consistent
# across the host and all VMs. Instead of copying values from host to VMs
# via the configHost anti-pattern, this module is imported by BOTH the
# host AND all VMs, ensuring consistency.
#
# This replaces the old modules.nix pattern which used:
#   configHost = config;
#   serviceModules.logging = { inherit (configHost.ghaf.logging) enable; };
#
# Now values flow directly:
#   Target Builder → sharedSystemConfig → VMs
#
# Usage:
#   # At target/builder level:
#   sharedConfig = import ./sharedSystemConfig.nix {
#     inherit lib;
#     variant = "debug";
#     givcEnable = config.ghaf.givc.enable;
#     # ... other host values
#   };
#
#   # Pass to VMs via specialArgs:
#   mkNetVm { systemConfigModule = sharedConfig; }
#
{
  lib,
  # Build variant: "debug" or "release"
  variant ? "debug",
  # Timezone for the system
  timeZone ? "UTC",

  # === Development Settings ===
  # Enable SSH daemon in development mode
  sshDaemonEnable ? (variant == "debug"),
  # Enable debug tools
  debugToolsEnable ? (variant == "debug"),
  # Enable nix-setup for development
  nixSetupEnable ? (variant == "debug"),

  # === GIVC Settings ===
  # Enable GIVC inter-VM communication
  givcEnable ? true,
  # Enable GIVC debug mode (disabled when logging is enabled to avoid info leaks)
  givcDebug ? (variant == "debug" && !loggingEnable),

  # === Logging Settings ===
  # Enable logging (defaults to false - profiles set this with proper listener address)
  loggingEnable ? false,
  # Logging listener configuration
  loggingListener ? { },
  # Logging server configuration
  loggingServer ? { },

  # === Security Settings ===
  # Enable security audit
  auditEnable ? true,

  # === Service Settings ===
  # Enable power manager
  powerManagerEnable ? true,
  # Enable performance monitoring
  performanceEnable ? true,

  # === User Settings ===
  # User profile configuration
  userProfile ? { },
  # Admin user configuration
  userAdmin ? { },
  # Managed users list
  userManaged ? [ ],

  # === Common Namespace ===
  # Common configuration shared across host and VMs
  commonConfig ? { },

  # === Reference Services ===
  # Reference services configuration (optional)
  referenceServices ? { },
}:
{
  # Profile settings
  ghaf.profiles = {
    debug.enable = lib.mkDefault (variant == "debug");
    release.enable = lib.mkDefault (variant == "release");
  };

  # Development settings
  ghaf.development = {
    ssh.daemon.enable = lib.mkDefault sshDaemonEnable;
    debug.tools.enable = lib.mkDefault debugToolsEnable;
    nix-setup.enable = lib.mkDefault nixSetupEnable;
  };

  # GIVC settings
  ghaf.givc = {
    enable = lib.mkDefault givcEnable;
    debug = lib.mkDefault givcDebug;
  };

  # Logging settings
  ghaf.logging = {
    enable = lib.mkDefault loggingEnable;
    listener = lib.mkDefault loggingListener;
    server = lib.mkDefault loggingServer;
  };

  # Security settings
  ghaf.security.audit.enable = lib.mkDefault auditEnable;

  # Service settings
  ghaf.services = {
    power-manager.enable = lib.mkDefault powerManagerEnable;
    performance.enable = lib.mkDefault performanceEnable;
  };

  # User settings
  ghaf.users = {
    profile = lib.mkDefault userProfile;
    admin = lib.mkDefault userAdmin;
    managed = lib.mkDefault userManaged;
  };

  # Common namespace
  ghaf.common = lib.mkDefault commonConfig;

  # Time settings
  time.timeZone = lib.mkDefault timeZone;
}
// lib.optionalAttrs (referenceServices != { }) {
  # Reference services (only if provided)
  ghaf.reference.services = lib.mkDefault referenceServices;
}
