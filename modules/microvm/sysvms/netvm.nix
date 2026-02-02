# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# Network VM Host Module - Uses evaluatedConfig for composition
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
  vmName = "net-vm";
  cfg = config.ghaf.virtualization.microvm.netvm;

  inherit (lib) hasAttrByPath optionalAttrs optionals;
  inherit (pkgs.stdenv.hostPlatform) isx86;

  fullVirtualization = isx86 && (hasAttrByPath [ "hardware" "devices" ] config.ghaf);

  mkNetVm = self.lib.vmBuilders.mkNetVm { inherit inputs lib; };
  sharedSystemConfig = config._module.specialArgs.sharedSystemConfig or { };

  baseNetVm = mkNetVm {
    inherit (config.nixpkgs.hostPlatform) system;
    systemConfigModule = sharedSystemConfig;
  };

  # === Common Host Bindings (TRULY DRY) ===
  commonHostBindings = self.lib.mkCommonHostBindings config {
    inherit vmName;
    tpmIndex = "0x81704000";
  };

  # === Net-VM Specific Bindings ===
  netVmSpecificBindings = {
    ghaf.development.debug.tools.net.enable = lib.mkDefault config.ghaf.development.debug.tools.enable;
    ghaf.security.ssh-tarpit = {
      inherit (config.ghaf.development.ssh.daemon) enable;
      listenAddress = config.ghaf.networking.hosts.${vmName}.ipv4;
    };
  };

  # Hardware passthrough modules (consumed from options)
  hardwareModules = optionals fullVirtualization [
    (optionalAttrs (hasAttrByPath [
      "ghaf"
      "hardware"
      "devices"
      "nics"
    ] config) config.ghaf.hardware.devices.nics)
    (optionalAttrs (hasAttrByPath [ "ghaf" "kernel" "netvm" ] config) config.ghaf.kernel.netvm)
    { config.ghaf.services.firmware.enable = true; }
    (optionalAttrs (hasAttrByPath [ "ghaf" "qemu" "netvm" ] config) config.ghaf.qemu.netvm)
    (optionalAttrs cfg.wifi { config.ghaf.services.wifi.enable = true; })
  ];

  commonModule = {
    config.ghaf = { inherit (config.ghaf) common; };
  };

  # === Extensions from Registry ===
  registryExtensions = config.ghaf.virtualization.microvm.extensions.netvm or [ ];
in
{
  options.ghaf.virtualization.microvm.netvm = {
    enable = lib.mkEnableOption "NetVM";

    wifi = lib.mkOption {
      type = lib.types.bool;
      default = isx86 && cfg.enable;
      description = "Enable WiFi module configuration.";
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
        message = "NetVM requires sharedSystemConfig to be provided via specialArgs.";
      }
    ];

    ghaf.common.extraNetworking.hosts.${vmName} = cfg.extraNetworking;

    microvm.vms.${vmName} = {
      autostart = !config.ghaf.microvm-boot.enable;
      restartIfChanged = false;

      evaluatedConfig = baseNetVm.extendModules {
        modules = [
          commonHostBindings
          netVmSpecificBindings
          commonModule
        ]
        ++ hardwareModules
        ++ registryExtensions;
      };
    };
  };
}
