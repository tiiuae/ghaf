# Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  config,
  lib,
  pkgs,
  ...
}: let
  inherit (lib) mkOption types optionals optionalAttrs mkEnableOption hasAttr;

  cfg = config.ghaf.virtualization.microvm;

  # Currently only x86 is supported by this module
  isX86 = pkgs.stdenv.hostPlatform.isx86;

  # Hardware passthrough modules
  hardwareModules = optionalAttrs isX86 {
    inherit
      (config.ghaf.hardware.passthrough)
      netvmPCIPassthroughModule
      audiovmPCIPassthroughModule
      audiovmKernelParams
      ;
  };

  # Firmware module
  firmwareModule = {
    config.ghaf.services.firmware.enable = true;
  };

  # Audio module configuration
  audioModule = optionalAttrs cfg.audiovm.audio {
    config.ghaf.services.audio.enable = true;
  };

  # Wifi module configuration
  wifiModule = optionalAttrs cfg.netvm.wifi {
    config.ghaf.services.wifi.enable = true;
  };

  # Reference services module
  referenceServiceModule = {
    config.ghaf = optionalAttrs (hasAttr "reference" config.ghaf) {
      reference = optionalAttrs (hasAttr "services" config.ghaf.reference) {
        inherit (config.ghaf.reference) services;
      };
    };
  };
in {
  options.ghaf.virtualization.microvm = {
    enable = mkEnableOption "Enable MicroVM module configuration. Only x86 is supported.";
    netvm.wifi = mkOption {
      type = types.bool;
      default = isX86 && cfg.netvm.enable;
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
  };

  config = {
    ghaf.virtualization.microvm = optionalAttrs isX86 {
      # Netvm modules
      netvm.extraModules = optionals cfg.netvm.enable [
        hardwareModules.netvmPCIPassthroughModule
        firmwareModule
        wifiModule
        referenceServiceModule
      ];
      # Audiovm modules
      audiovm.extraModules = optionals cfg.audiovm.enable [
        hardwareModules.audiovmPCIPassthroughModule
        hardwareModules.audiovmKernelParams
        audioModule
      ];
    };
  };
}
