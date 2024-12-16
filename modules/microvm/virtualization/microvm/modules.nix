# Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  config,
  lib,
  pkgs,
  ...
}:
let
  inherit (builtins) hasAttr;
  inherit (lib)
    mkOption
    types
    optionals
    optionalAttrs
    ;

  cfg = config.ghaf.virtualization.microvm;

  # Currently only x86 with hw definition supported
  inherit (pkgs.stdenv.hostPlatform) isx86;
  fullVirtualization =
    isx86 && (hasAttr "hardware" config.ghaf) && (hasAttr "devices" config.ghaf.hardware);

  # Hardware devices passthrough modules
  deviceModules = optionalAttrs fullVirtualization {
    inherit (config.ghaf.hardware.devices)
      netvmPCIPassthroughModule
      audiovmPCIPassthroughModule
      guivmPCIPassthroughModule
      guivmVirtioInputHostEvdevModule
      ;
  };

  # Kernel configurations
  kernelConfigs = optionalAttrs fullVirtualization { inherit (config.ghaf.kernel) guivm audiovm; };

  # Firmware module
  firmwareModule = {
    config.ghaf.services.firmware.enable = true;
  };

  # Qemu configuration modules
  qemuModules = {
    inherit (config.ghaf.qemu) guivm;
    inherit (config.ghaf.qemu) audiovm;
  };

  # Service modules
  serviceModules = {
    # Givc module
    givc = {
      config.ghaf.givc.enable = config.ghaf.givc.enable;
    };

    # Audio module
    audio = optionalAttrs cfg.audiovm.audio { config.ghaf.services.audio.enable = true; };

    # Bluetooth module
    bluetooth = optionalAttrs cfg.audiovm.audio { config.ghaf.services.bluetooth.enable = true; };

    # Wifi module
    wifi = optionalAttrs cfg.netvm.wifi { config.ghaf.services.wifi.enable = true; };

    # Fprint module
    fprint = optionalAttrs cfg.guivm.fprint { config.ghaf.services.fprint.enable = true; };

    # XDG opener
    xdgOpener = {
      config.ghaf.services.xdgopener.enable = true;
    };

    # Yubikey module
    yubikey = optionalAttrs cfg.guivm.yubikey { config.ghaf.services.yubikey.enable = true; };

    # Common namespace to share (built-time) between host and VMs
    commonNamespace = {
      config.ghaf.namespaces = config.ghaf.namespaces;
    };
  };

  # User account settings
  managedUserAccounts = {
    config.ghaf.users.admin = config.ghaf.users.admin;
    config.ghaf.users.managed = config.ghaf.users.managed;
  };

  # Reference services module
  referenceServiceModule = {
    config.ghaf = optionalAttrs (hasAttr "reference" config.ghaf) {
      reference = optionalAttrs (hasAttr "services" config.ghaf.reference) {
        inherit (config.ghaf.reference) services;
      };
    };
  };

  # Reference programs module
  referenceProgramsModule = {
    config.ghaf = optionalAttrs (hasAttr "reference" config.ghaf) {
      reference = optionalAttrs (hasAttr "programs" config.ghaf.reference) {
        inherit (config.ghaf.reference) programs;
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
    ghaf.virtualization.microvm = optionalAttrs fullVirtualization {
      # Netvm modules
      netvm.extraModules = optionals cfg.netvm.enable [
        deviceModules.netvmPCIPassthroughModule
        firmwareModule
        serviceModules.wifi
        serviceModules.givc
        referenceServiceModule
        managedUserAccounts
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
        managedUserAccounts
      ];
      # Guivm modules
      guivm.extraModules = optionals cfg.guivm.enable [
        deviceModules.guivmPCIPassthroughModule
        deviceModules.guivmVirtioInputHostEvdevModule
        kernelConfigs.guivm
        firmwareModule
        qemuModules.guivm
        serviceModules.fprint
        serviceModules.yubikey
        serviceModules.xdgOpener
        serviceModules.commonNamespace
        serviceModules.givc
        referenceProgramsModule
        managedUserAccounts
      ];
      adminvm.extraModules = optionals cfg.adminvm.enable [
        serviceModules.givc
        managedUserAccounts
      ];
      appvm.extraModules = optionals cfg.appvm.enable [
        serviceModules.givc
        managedUserAccounts
      ];
    };
  };
}
