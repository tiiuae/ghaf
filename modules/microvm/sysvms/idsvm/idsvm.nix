# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# IDS VM Host Module - Uses evaluatedConfig for composition
#
# Key features:
# - Common host bindings via mkCommonHostBindings (truly DRY - only vmName + tpmIndex)
# - IDS-specific bindings (mitmproxy) separate
# - Downstream extends via: ghaf.lib.vmConfigs.idsvm.extendModules { ... }
#
{
  config,
  lib,
  self,
  inputs,
  ...
}:
let
  vmName = "ids-vm";
  cfg = config.ghaf.virtualization.microvm.idsvm;

  mkIdsVm = self.lib.vmBuilders.mkIdsVm { inherit inputs lib; };
  sharedSystemConfig = config._module.specialArgs.sharedSystemConfig or { };

  baseIdsVm = mkIdsVm {
    inherit (config.nixpkgs.hostPlatform) system;
    systemConfigModule = sharedSystemConfig;
  };

  # === Common Host Bindings (TRULY DRY) ===
  commonHostBindings = self.lib.mkCommonHostBindings config {
    inherit vmName;
    tpmIndex = "0x81705000";
  };

  # === IDS-VM Specific Bindings ===
  idsVmSpecificBindings = {
    # Enable mitmproxy if configured on host
    ghaf.virtualization.microvm.idsvm.mitmproxy.enable =
      config.ghaf.virtualization.microvm.idsvm.mitmproxy.enable;
  };

  commonModule = {
    config.ghaf = { inherit (config.ghaf) common; };
  };

  # === Extensions from Registry ===
  registryExtensions = config.ghaf.virtualization.microvm.extensions.idsvm or [ ];
in
{
  imports = [ ./mitmproxy ];

  options.ghaf.virtualization.microvm.idsvm = {
    enable = lib.mkEnableOption "Whether to enable IDS-VM on the system";

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
        message = "IDS VM requires sharedSystemConfig to be provided via specialArgs.";
      }
    ];

    ghaf.common.extraNetworking.hosts.${vmName} = cfg.extraNetworking;

    microvm.vms.${vmName} = {
      autostart = true;

      evaluatedConfig = baseIdsVm.extendModules {
        modules = [
          commonHostBindings
          idsVmSpecificBindings
          commonModule
        ]
        ++ registryExtensions;
      };
    };
  };
}
