# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# Shared VM Module Configuration
#
# This module adds common extraModules to each VM type based on host configuration.
# It passes host-specific settings (devices, kernels, qemu configs) via inline modules
# that get added to VMs.
#
# Global settings (givc, logging, audit, power, performance) are now available via
# globalConfig specialArg, but we still pass them here for modules that don't
# directly use globalConfig yet.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  inherit (lib)
    mkOption
    types
    optionals
    optionalAttrs
    hasAttrByPath
    ;

  cfg = config.ghaf.virtualization.microvm;
  hostGlobalConfig = config.ghaf.global-config;

  # Host configuration reference for hardware-specific settings
  configHost = config;

  # Currently only x86 with hw definition supported
  inherit (pkgs.stdenv.hostPlatform) isx86;
  fullVirtualization =
    isx86
    && (hasAttrByPath [
      "hardware"
      "devices"
    ] config.ghaf);

  # Hardware devices passthrough modules (host-specific, can't use globalConfig)
  deviceModules = optionalAttrs fullVirtualization {
    inherit (configHost.ghaf.hardware.devices)
      nics
      audio
      gpus
      evdev
      ;
  };

  # Kernel configurations (host-specific, can't use globalConfig)
  kernelConfigs = optionalAttrs fullVirtualization {
    inherit (configHost.ghaf.kernel) guivm audiovm netvm;
  };

  # Firmware module
  firmwareModule = {
    config.ghaf.services.firmware.enable = true;
  };

  # Qemu configuration modules (host-specific, can't use globalConfig)
  qemuModules = {
    inherit (configHost.ghaf.qemu) guivm;
    inherit (configHost.ghaf.qemu) audiovm;
    inherit (configHost.ghaf.qemu) netvm;
  };

  # Common namespace to pass parameters at built-time from host to VMs
  commonModule = {
    config.ghaf = {
      inherit (configHost.ghaf) common;
    };
  };

  # Service modules - these now use globalConfig where available
  # Note: VMs receive globalConfig via specialArgs, so these modules can
  # access it if they're written as functions ({ globalConfig, ... }: ...)
  serviceModules = {
    # Givc module - uses globalConfig values synced from backward compat
    givc = {
      config.ghaf.givc = {
        inherit (hostGlobalConfig.givc) enable;
        inherit (hostGlobalConfig.givc) debug;
      };
    };

    # Bluetooth module
    bluetooth = optionalAttrs cfg.audiovm.audio { config.ghaf.services.bluetooth.enable = true; };

    # Xpadneo module
    xpadneo = optionalAttrs cfg.audiovm.audio { config.ghaf.services.xpadneo.enable = false; };

    # Wifi module
    wifi = optionalAttrs cfg.netvm.wifi { config.ghaf.services.wifi.enable = true; };

    # Fprint module
    fprint = optionalAttrs cfg.guivm.fprint { config.ghaf.services.fprint.enable = true; };

    # Yubikey module
    yubikey = optionalAttrs cfg.guivm.yubikey { config.ghaf.services.yubikey.enable = true; };

    # Brightness module
    brightness = optionalAttrs cfg.guivm.brightness { config.ghaf.services.brightness.enable = true; };

    # Logging module - uses globalConfig values
    logging = {
      config.ghaf.logging = {
        inherit (hostGlobalConfig.logging) enable;
        listener.address = hostGlobalConfig.logging.listener.address;
        server.endpoint = hostGlobalConfig.logging.server.endpoint;
      };
    };

    # Audit module - uses globalConfig values
    audit = {
      config.ghaf.security.audit = {
        inherit (hostGlobalConfig.security.audit) enable;
      };
    };

    # Power management module - uses globalConfig values
    power = {
      config.ghaf.services.power-manager = {
        inherit (hostGlobalConfig.services.power-manager) enable;
      };
    };

    # Performance module - uses globalConfig values
    performance = {
      config.ghaf.services.performance = {
        inherit (hostGlobalConfig.services.performance) enable;
      };
    };
  };

  # User account settings (host-specific, can't use globalConfig)
  managedUserAccounts = {
    config.ghaf.users = {
      inherit (configHost.ghaf.users) profile;
      inherit (configHost.ghaf.users) admin;
      inherit (configHost.ghaf.users) managed;
    };
  };

  # Reference services module (host-specific, can't use globalConfig)
  referenceServiceModule = {
    config.ghaf =
      optionalAttrs
        (hasAttrByPath [
          "reference"
          "services"
        ] config.ghaf)
        {
          reference = {
            inherit (configHost.ghaf.reference) services;
          };
        };
  };

in
{
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
      # Netvm modules
      netvm.extraModules =
        optionals cfg.netvm.enable [
          serviceModules.logging
          serviceModules.givc
          commonModule
          managedUserAccounts
        ]
        ++ optionals (cfg.netvm.enable && fullVirtualization) [
          deviceModules.nics
          kernelConfigs.netvm
          firmwareModule
          qemuModules.netvm
          serviceModules.wifi
          serviceModules.audit
          serviceModules.power
          serviceModules.performance
          referenceServiceModule
        ];
      # Audiovm modules
      audiovm.extraModules =
        optionals cfg.audiovm.enable [
          serviceModules.logging
          serviceModules.givc
          commonModule
          managedUserAccounts
        ]
        ++ optionals (cfg.audiovm.enable && fullVirtualization) [
          deviceModules.audio
          kernelConfigs.audiovm
          firmwareModule
          qemuModules.audiovm
          serviceModules.audit
          serviceModules.bluetooth
          serviceModules.xpadneo
          serviceModules.power
          serviceModules.performance
          managedUserAccounts
        ];
      # Guivm modules
      guivm.extraModules =
        optionals cfg.guivm.enable [
          serviceModules.logging
          serviceModules.givc
          commonModule
          managedUserAccounts
        ]
        ++ optionals (cfg.guivm.enable && fullVirtualization) [
          deviceModules.gpus
          deviceModules.evdev
          kernelConfigs.guivm
          firmwareModule
          qemuModules.guivm
          serviceModules.fprint
          serviceModules.yubikey
          serviceModules.audit
          serviceModules.brightness
          serviceModules.power
          serviceModules.performance
          referenceServiceModule
        ];

      # Adminvm modules - MIGRATED to adminvm-base.nix and adminvm-features
      # Service configs now come via globalConfig/hostConfig in adminvm-base.nix

      # Appvm modules
      appvm.extraModules =
        optionals cfg.appvm.enable [
          serviceModules.logging
          serviceModules.givc
          commonModule
          managedUserAccounts
        ]
        ++ optionals (cfg.appvm.enable && fullVirtualization) [
          serviceModules.audit
        ];

      # IDS VM modules - MIGRATED to idsvm-base.nix
      # The commonModule functionality is now included directly in idsvm-base.nix
      # via hostConfig.common assignment. No extraModules needed.
    };
  };
}
