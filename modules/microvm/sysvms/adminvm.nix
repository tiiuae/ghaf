# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# Admin VM Host Module - Uses evaluatedConfig for composition
#
# Key features:
# - Common host bindings via mkCommonHostBindings (truly DRY - only vmName + tpmIndex)
# - Admin-specific bindings (logging SERVER, storage directories) separate
# - Downstream extends via: ghaf.lib.vmConfigs.adminvm.extendModules { ... }
#
{
  config,
  lib,
  self,
  inputs,
  ...
}:
let
  vmName = "admin-vm";
  cfg = config.ghaf.virtualization.microvm.adminvm;

  mkAdminVm = self.lib.vmBuilders.mkAdminVm { inherit inputs lib; };
  sharedSystemConfig = config._module.specialArgs.sharedSystemConfig or { };

  baseAdminVm = mkAdminVm {
    inherit (config.nixpkgs.hostPlatform) system;
    systemConfigModule = sharedSystemConfig;
  };

  # === Common Host Bindings (TRULY DRY) ===
  commonHostBindings = self.lib.mkCommonHostBindings config {
    inherit vmName;
    tpmIndex = "0x81701000";
  };

  # === Admin-VM Specific Bindings ===
  # Admin-VM is special - it runs the logging SERVER
  adminVmSpecificBindings =
    { lib, ... }:
    {
      # Storage encryption directories (admin-vm specific)
      ghaf.storagevm.directories = lib.mkIf config.ghaf.virtualization.storagevm-encryption.enable [
        "/var/lib/swtpm"
      ];

      # Logging SERVER configuration (admin-vm hosts the logging server)
      ghaf.logging.server = {
        inherit (config.ghaf.logging) enable;
        endpoint = config.ghaf.logging.server.endpoint or "";
        tls = {
          remoteCAFile = null;
          certFile = "/etc/givc/cert.pem";
          keyFile = "/etc/givc/key.pem";
          serverName = "loki.ghaflogs.vedenemo.dev";
          minVersion = "TLS12";
          terminator = {
            backendPort = 3101;
            verifyClients = true;
          };
        };
      };
    };

  commonModule = {
    config.ghaf = { inherit (config.ghaf) common; };
  };

  # === Extensions from Registry ===
  registryExtensions = config.ghaf.virtualization.microvm.extensions.adminvm or [ ];
in
{
  options.ghaf.virtualization.microvm.adminvm = {
    enable = lib.mkEnableOption "AdminVM";

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
        message = "AdminVM requires sharedSystemConfig to be provided via specialArgs.";
      }
    ];

    ghaf.common.extraNetworking.hosts.${vmName} = cfg.extraNetworking;

    microvm.vms.${vmName} = {
      autostart = true;

      evaluatedConfig = baseAdminVm.extendModules {
        modules = [
          commonHostBindings
          adminVmSpecificBindings
          commonModule
        ]
        ++ registryExtensions;
      };
    };
  };
}
