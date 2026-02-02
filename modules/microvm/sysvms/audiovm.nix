# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# Audio VM Host Module - Uses evaluatedConfig for composition
#
# Key features:
# - Common host bindings via mkCommonHostBindings (truly DRY - only vmName + tpmIndex)
# - Consumes hardware passthrough config from options (no extraModules)
# - Downstream extends via extendModules on exported vmConfigs
#
{
  config,
  lib,
  pkgs,
  self,
  inputs,
  ...
}:
let
  vmName = "audio-vm";
  cfg = config.ghaf.virtualization.microvm.audiovm;

  inherit (lib) hasAttrByPath optionalAttrs optionals;
  inherit (pkgs.stdenv.hostPlatform) isx86;

  fullVirtualization = isx86 && (hasAttrByPath [ "hardware" "devices" ] config.ghaf);

  mkAudioVm = self.lib.vmBuilders.mkAudioVm { inherit inputs lib; };
  sharedSystemConfig = config._module.specialArgs.sharedSystemConfig or { };

  baseAudioVm = mkAudioVm {
    inherit (config.nixpkgs.hostPlatform) system;
    systemConfigModule = sharedSystemConfig;
  };

  # === Common Host Bindings (TRULY DRY) ===
  commonHostBindings = self.lib.mkCommonHostBindings config {
    inherit vmName;
    tpmIndex = "0x81702000";
  };

  # Hardware passthrough modules (consumed from options)
  hardwareModules = optionals fullVirtualization [
    (optionalAttrs (hasAttrByPath [
      "ghaf"
      "hardware"
      "devices"
      "audio"
    ] config) config.ghaf.hardware.devices.audio)
    (optionalAttrs (hasAttrByPath [ "ghaf" "kernel" "audiovm" ] config) config.ghaf.kernel.audiovm)
    { config.ghaf.services.firmware.enable = true; }
    (optionalAttrs (hasAttrByPath [ "ghaf" "qemu" "audiovm" ] config) config.ghaf.qemu.audiovm)
    (optionalAttrs cfg.audio { config.ghaf.services.bluetooth.enable = true; })
    { config.ghaf.services.xpadneo.enable = false; }
  ];

  commonModule = {
    config.ghaf = { inherit (config.ghaf) common; };
  };

  # === Extensions from Registry ===
  registryExtensions = config.ghaf.virtualization.microvm.extensions.audiovm or [ ];
in
{
  options.ghaf.virtualization.microvm.audiovm = {
    enable = lib.mkEnableOption "AudioVM";

    audio = lib.mkOption {
      type = lib.types.bool;
      default = cfg.enable;
      description = "Enable Audio module configuration.";
    };

    extraNetworking = lib.mkOption {
      type = lib.types.networking;
      description = "Extra Networking option";
      default = { };
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = sharedSystemConfig != { };
        message = "AudioVM requires sharedSystemConfig to be provided via specialArgs.";
      }
    ];

    ghaf.common.extraNetworking.hosts.${vmName} = cfg.extraNetworking;

    microvm.vms.${vmName} = {
      autostart = !config.ghaf.microvm-boot.enable;

      evaluatedConfig = baseAudioVm.extendModules {
        modules = [
          commonHostBindings
          commonModule
        ]
        ++ hardwareModules
        ++ registryExtensions;
      };
    };
  };
}
