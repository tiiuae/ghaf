# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# IDS VM Configuration Module
#
# This module uses the globalConfig pattern:
# - Global settings (debug, development, logging, storage, idsvm) come via globalConfig specialArg
#
# The VM configuration is self-contained and does not reference `configHost`.
{
  config,
  lib,
  inputs,
  ...
}:
let
  vmName = "ids-vm";
  hostGlobalConfig = config.ghaf.global-config;

  idsvmBaseConfiguration = {
    _file = ./idsvm.nix;
    imports = [
      inputs.preservation.nixosModules.preservation
      inputs.self.nixosModules.vm-modules
      inputs.self.nixosModules.givc
      inputs.self.nixosModules.hardware-x86_64-guest-kernel
      inputs.self.nixosModules.profiles
      (
        {
          lib,
          pkgs,
          globalConfig,
          ...
        }:
        {
          imports = [
            ./mitmproxy
          ];

          ghaf = {
            type = "system-vm";
            profiles.debug.enable = lib.mkDefault globalConfig.debug.enable;

            virtualization.microvm.idsvm.mitmproxy.enable = globalConfig.idsvm.mitmproxy.enable;

            development = {
              # NOTE: SSH port also becomes accessible on the network interface
              #       that has been passed through to NetVM
              ssh.daemon.enable = lib.mkDefault globalConfig.development.ssh.daemon.enable;
              debug.tools.enable = lib.mkDefault globalConfig.development.debug.tools.enable;
              nix-setup.enable = lib.mkDefault globalConfig.development.nix-setup.enable;
            };
            virtualization.microvm.vm-networking = {
              enable = true;
              isGateway = true;
              inherit vmName;
            };

            logging = {
              inherit (configHost.ghaf.logging) enable listener;
              client.enable = configHost.ghaf.logging.enable;
            };
          };

          system.stateVersion = lib.trivial.release;

          nixpkgs = {
            buildPlatform.system = globalConfig.platform.buildSystem;
            hostPlatform.system = globalConfig.platform.hostSystem;
          };

          environment.systemPackages = [
            pkgs.snort # TODO: put into separate module
          ]
          ++ (lib.optional globalConfig.debug.enable pkgs.tcpdump);

          microvm = {
            hypervisor = "qemu";
            optimize.enable = true;

            # Shared store (when not using storeOnDisk)
            shares = lib.optionals (!globalConfig.storage.storeOnDisk) [
              {
                tag = "ro-store";
                source = "/nix/store";
                mountPoint = "/nix/.ro-store";
                proto = "virtiofs";
              }
            ];

            writableStoreOverlay = lib.mkIf (!globalConfig.storage.storeOnDisk) "/nix/.rw-store";
          }
          // lib.optionalAttrs globalConfig.storage.storeOnDisk {
            storeOnDisk = true;
            storeDiskType = "erofs";
            storeDiskErofsFlags = [
              "-zlz4hc"
              "-Eztailpacking"
            ];
          };
        }
      )
    ];
  };
  cfg = config.ghaf.virtualization.microvm.idsvm;
in
{
  imports = [
    ./mitmproxy
  ];

  options.ghaf.virtualization.microvm.idsvm = {
    enable = lib.mkEnableOption "Whether to enable IDS-VM on the system";

    evaluatedConfig = lib.mkOption {
      type = lib.types.nullOr lib.types.unspecified;
      default = null;
      description = ''
        Pre-evaluated NixOS configuration for IDS VM.
        When set (by profiles like mvp-user-trial-extras), uses this instead of building inline.
        This enables the layered composition pattern with extendModules.
      '';
    };

    extraModules = lib.mkOption {
      description = ''
        List of additional modules to be imported and evaluated as part of
        IDSVM's NixOS configuration.

        DEPRECATED: This option is deprecated. Use the evaluatedConfig pattern instead:
          ghaf.virtualization.microvm.idsvm.evaluatedConfig =
            config.ghaf.profiles.laptop-x86.idsvmBase.extendModules { modules = [...]; };
      '';
      default = [ ];
    };
    extraNetworking = lib.mkOption {
      type = lib.types.networking;
      description = "Extra Networking option";
      default = { };
    };
  };

  config = lib.mkIf cfg.enable {
    ghaf.common.extraNetworking.hosts.${vmName} = cfg.extraNetworking;

    # Deprecation warning for extraModules
    warnings = lib.optional (cfg.extraModules != [ ]) ''
      ghaf.virtualization.microvm.idsvm.extraModules is deprecated.
      Please migrate to the evaluatedConfig pattern using idsvm-base.nix.
      See modules/microvm/sysvms/idsvm/idsvm-base.nix for the new approach.
    '';

    microvm.vms."${vmName}" =
      if cfg.evaluatedConfig != null then
        # New path: Use pre-evaluated config from profile
        # This is the recommended approach for laptop targets
        {
          autostart = true;
          inherit (inputs) nixpkgs;
          inherit (cfg) evaluatedConfig;
        }
      else
        # Legacy path: Build config inline
        # Used by non-laptop targets (Jetson, etc.) that don't have laptop-x86 profile
        {
          autostart = true;
          inherit (inputs) nixpkgs;
          specialArgs = lib.ghaf.mkVmSpecialArgs {
            inherit lib inputs;
            globalConfig = hostGlobalConfig;
          };

          config = idsvmBaseConfiguration // {
            imports = idsvmBaseConfiguration.imports ++ cfg.extraModules;
          };
        };
  };
}
