# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# VM Feature Options Module
#
# This module provides feature flag options for VMs.
# The actual module configurations have been migrated to:
#   - *-base.nix modules (via globalConfig/hostConfig)
#   - hardware.definition.*.extraModules (via pci-ports.nix/pci-rules.nix)
#
# These options remain for backward compatibility and may be removed in a future release.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  inherit (lib) mkOption types;

  cfg = config.ghaf.virtualization.microvm;

  # Currently only x86 with hw definition supported
  inherit (pkgs.stdenv.hostPlatform) isx86;
in
{
  _file = ./modules.nix;

  options.ghaf.virtualization.microvm = {
    netvm.wifi = mkOption {
      type = types.bool;
      default = isx86 && cfg.netvm.enable;
      description = ''
        Enable Wifi module configuration.
      '';
    };
    audiovm.audio = mkOption {
      type = types.bool;
      default = cfg.audiovm.enable;
      description = ''
        Enable Audio module configuration.
      '';
    };
    guivm.fprint = mkOption {
      type = types.bool;
      default = cfg.guivm.enable;
      description = ''
        Enable Fingerprint module configuration.
      '';
    };
    guivm.yubikey = mkOption {
      type = types.bool;
      default = cfg.guivm.enable;
      description = ''
        Enable Yubikey module configuration.
      '';
    };
    guivm.brightness = mkOption {
      type = types.bool;
      default = cfg.guivm.enable;
      description = ''
        brightness module configuration.
      '';
    };
  };

  config = {
    # System VM configurations
    ghaf.virtualization.microvm = {
      # Net VM modules - MIGRATED to netvm-base.nix
      # Service modules (logging, givc, wifi, audit, power, performance) are now in netvm-base.nix
      # Hardware modules (devices.nics, kernel, qemu) go via hardware.definition.netvm.extraModules
      # commonModule functionality is now in netvm-base.nix via hostConfig.common
      # managedUserAccounts functionality is now in netvm-base.nix via hostConfig.users
      # Note: Jetson and other non-laptop platforms continue to use netvm.extraModules directly

      # Audio VM modules - MIGRATED to audiovm-base.nix and audiovm-features/
      # Service modules (logging, givc, audit, power, performance) are now in audiovm-base.nix
      # Hardware modules (devices, kernel, qemu, bluetooth, xpadneo) are now in audiovm-features/
      # commonModule functionality is now in audiovm-base.nix via hostConfig.common
      # No extraModules needed.

      # GUI VM modules - MIGRATED to guivm-base.nix and hardware.definition
      # Service modules (logging, givc, fprint, yubikey, brightness, audit, power, performance)
      #   are now in guivm-base.nix via globalConfig
      # Hardware modules (devices.gpus, evdev, kernel, qemu, firmware)
      #   go via hardware.definition.guivm.extraModules (set by pci-ports.nix/pci-rules.nix)
      # commonModule functionality is now in guivm-base.nix via hostConfig.common
      # managedUserAccounts functionality is now in guivm-base.nix via hostConfig.users
      # referenceServiceModule is imported via profile extendModules (mvp-user-trial.nix)
      # No extraModules needed.

      # Adminvm modules - MIGRATED to adminvm-base.nix and adminvm-features
      # Service configs now come via globalConfig/hostConfig in adminvm-base.nix

      # App VM modules - MIGRATED to appvm-base.nix
      # Service modules (logging, givc, audit) are now in appvm-base.nix via globalConfig
      # commonModule functionality is now in appvm-base.nix via hostConfig.common
      # managedUserAccounts functionality is now in appvm-base.nix via hostConfig.users
      # No extraModules needed - all config is in appvm-base.nix

      # IDS VM modules - MIGRATED to idsvm-base.nix
      # The commonModule functionality is now included directly in idsvm-base.nix
      # via hostConfig.common assignment. No extraModules needed.
    };
  };
}
