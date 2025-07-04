# Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
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

  # Host configuration; for clarity
  configHost = config;

  # Currently only x86 with hw definition supported
  inherit (pkgs.stdenv.hostPlatform) isx86;
  fullVirtualization =
    isx86
    && (hasAttrByPath [
      "hardware"
      "devices"
    ] config.ghaf);

  # Hardware devices passthrough modules
  deviceModules = optionalAttrs fullVirtualization {
    inherit (configHost.ghaf.hardware.devices)
      netvmPCIPassthroughModule
      audiovmPCIPassthroughModule
      guivmPCIPassthroughModule
      guivmVirtioInputHostEvdevModule
      ;
  };

  # Kernel configurations
  kernelConfigs = optionalAttrs fullVirtualization {
    inherit (configHost.ghaf.kernel) guivm audiovm netvm;
  };

  # Firmware module
  firmwareModule = {
    config.ghaf.services.firmware.enable = true;
  };

  # Qemu configuration modules
  qemuModules = {
    inherit (configHost.ghaf.qemu) guivm;
    inherit (configHost.ghaf.qemu) audiovm;
  };

  # Common namespace to pass parameters at built-time from host to VMs
  commonModule = {
    config.ghaf = {
      inherit (configHost.ghaf) common;
    };
  };

  # Service modules
  serviceModules = {
    # Givc module
    givc = {
      config.ghaf.givc = {
        inherit (configHost.ghaf.givc) enable;
        inherit (configHost.ghaf.givc) debug;
      };
    };

    # Graphics profiles module
    graphics = {
      config.ghaf.profiles.graphics = {
        inherit (configHost.ghaf.profiles.graphics) compositor renderer allowSuspend;
        idleManagement = {
          inherit (configHost.ghaf.profiles.graphics.idleManagement) enable;
        };
      };
    };

    # Audio module
    audio = optionalAttrs cfg.audiovm.audio { config.ghaf.services.audio.enable = true; };

    # Bluetooth module
    bluetooth = optionalAttrs cfg.audiovm.audio { config.ghaf.services.bluetooth.enable = true; };

    # Wifi module
    wifi = optionalAttrs cfg.netvm.wifi { config.ghaf.services.wifi.enable = true; };

    # Fprint module
    fprint = optionalAttrs cfg.guivm.fprint { config.ghaf.services.fprint.enable = true; };

    # Yubikey module
    yubikey = optionalAttrs cfg.guivm.yubikey { config.ghaf.services.yubikey.enable = true; };

    # Logging module
    logging = {
      config.ghaf.logging = {
        inherit (configHost.ghaf.logging) enable;
        listener = {
          inherit (configHost.ghaf.logging.listener) address;
        };
        server = {
          inherit (configHost.ghaf.logging.server) endpoint;
        };
      };
    };
  };

  # User account settings
  managedUserAccounts = {
    config.ghaf.users = {
      inherit (configHost.ghaf.users) admin;
      inherit (configHost.ghaf.users) managed;
    };
  };

  # Reference services module
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
  };

  config = {
    # System VM configurations
    ghaf.virtualization.microvm =
      optionalAttrs fullVirtualization {
        # Netvm modules
        netvm.extraModules = optionals cfg.netvm.enable [
          deviceModules.netvmPCIPassthroughModule
          kernelConfigs.netvm
          firmwareModule
          serviceModules.wifi
          serviceModules.givc
          serviceModules.logging
          referenceServiceModule
          managedUserAccounts
          commonModule
        ];
        # Audiovm modules
        audiovm.extraModules = optionals cfg.audiovm.enable [
          deviceModules.audiovmPCIPassthroughModule
          kernelConfigs.audiovm
          firmwareModule
          qemuModules.audiovm
          serviceModules.audio
          serviceModules.givc
          serviceModules.bluetooth
          serviceModules.logging
          managedUserAccounts
          commonModule
        ];
        # Guivm modules
        guivm.extraModules = optionals cfg.guivm.enable [
          deviceModules.guivmPCIPassthroughModule
          deviceModules.guivmVirtioInputHostEvdevModule
          kernelConfigs.guivm
          firmwareModule
          qemuModules.guivm
          serviceModules.graphics
          serviceModules.fprint
          serviceModules.yubikey
          serviceModules.givc
          serviceModules.logging
          referenceServiceModule
          # TODO: WHat is this and why it had to be disabled?
          # referenceProgramsModule
          managedUserAccounts
          commonModule
        ];
        # Adminvm modules
        adminvm.extraModules = optionals cfg.adminvm.enable [
          serviceModules.givc
          serviceModules.logging
          managedUserAccounts
          commonModule
        ];
        # Appvm modules
        appvm.extraModules = optionals cfg.appvm.enable [
          serviceModules.givc
          serviceModules.logging
          managedUserAccounts
          commonModule
        ];
        # Idsvm modules
        idsvm.extraModules = optionals cfg.idsvm.enable [
          commonModule
        ];
      }
      // {
        # Common modules
        gpuvm.extraModules = optionals cfg.gpuvm.enable [
          managedUserAccounts
          commonModule
        ];
      };
  };
}
