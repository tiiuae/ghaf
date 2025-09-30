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
      nics
      audio
      gpus
      evdev
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

    # Xpadneo module
    xpadneo = optionalAttrs cfg.audiovm.audio { config.ghaf.services.xpadneo.enable = true; };

    # Wifi module
    wifi = optionalAttrs cfg.netvm.wifi { config.ghaf.services.wifi.enable = true; };

    # Fprint module
    fprint = optionalAttrs cfg.guivm.fprint { config.ghaf.services.fprint.enable = true; };

    # Yubikey module
    yubikey = optionalAttrs cfg.guivm.yubikey { config.ghaf.services.yubikey.enable = true; };

    # Brightness module
    brightness = optionalAttrs cfg.guivm.brightness { config.ghaf.services.brightness.enable = true; };

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

    # Audit module
    audit = {
      config.ghaf.security.audit = {
        inherit (configHost.ghaf.security.audit) enable;
      };
    };

    # Power management module
    power = {
      config.ghaf.services.power-manager = {
        inherit (configHost.ghaf.services.power-manager) enable;
      };
    };
  };

  # User account settings
  managedUserAccounts = {
    config.ghaf.users = {
      inherit (configHost.ghaf.users) profile;
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
          serviceModules.wifi
          serviceModules.audit
          serviceModules.power
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
          serviceModules.audio
          serviceModules.audit
          serviceModules.bluetooth
          serviceModules.xpadneo
          serviceModules.power
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
          serviceModules.graphics
          serviceModules.fprint
          serviceModules.yubikey
          serviceModules.audit
          serviceModules.brightness
          serviceModules.power
          referenceServiceModule
        ];

      # Adminvm modules
      adminvm.extraModules =
        optionals cfg.adminvm.enable [
          serviceModules.logging
          serviceModules.givc
          commonModule
          managedUserAccounts
        ]
        ++ optionals (cfg.adminvm.enable && fullVirtualization) [
          serviceModules.audit
        ];
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
      # Idsvm modules
      idsvm.extraModules = optionals cfg.idsvm.enable [
        commonModule
      ];
    };
  };
}
