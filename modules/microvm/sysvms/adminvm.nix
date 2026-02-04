# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# Admin VM Configuration Module
#
# This module uses the globalConfig pattern:
# - Global settings come via globalConfig specialArg
# - Host-specific settings come via hostConfig specialArg
#
# For new profiles, use evaluatedConfig with adminvmBase from laptop-x86:
#   ghaf.virtualization.microvm.adminvm.evaluatedConfig =
#     config.ghaf.profiles.laptop-x86.adminvmBase;
#
{
  config,
  lib,
  inputs,
  ...
}:
let
  vmName = "admin-vm";
  hostGlobalConfig = config.ghaf.global-config;

  # Legacy inline configuration (for non-laptop targets that don't use evaluatedConfig)
  adminvmBaseConfiguration = {
    _file = ./adminvm.nix;
    imports = [
      inputs.preservation.nixosModules.preservation
      inputs.self.nixosModules.givc
      inputs.self.nixosModules.hardware-x86_64-guest-kernel
      inputs.self.nixosModules.vm-modules
      inputs.self.nixosModules.profiles
      (
        {
          lib,
          globalConfig,
          hostConfig,
          ...
        }:
        {
          ghaf = {
            # Profiles - use globalConfig for propagated settings
            profiles.debug.enable = lib.mkDefault globalConfig.debug.enable;
            development = {
              ssh.daemon.enable = lib.mkDefault globalConfig.development.ssh.daemon.enable;
              debug.tools.enable = lib.mkDefault globalConfig.development.debug.tools.enable;
              nix-setup.enable = lib.mkDefault globalConfig.development.nix-setup.enable;
            };

            # Networking hosts - from hostConfig
            networking.hosts = hostConfig.networking.hosts or { };

            # Common namespace - from hostConfig
            common = hostConfig.common or { };

            # User configuration - from hostConfig
            users = {
              profile = hostConfig.users.profile or { };
              admin = hostConfig.users.admin or { };
              managed = hostConfig.users.managed or { };
            };

            # System
            type = "admin-vm";
            systemd = {
              enable = true;
              withName = "adminvm-systemd";
              withLocaled = true;
              withNss = true;
              withResolved = true;
              withPolkit = true;
              withTimesyncd = true;
              withDebug = globalConfig.debug.enable;
              withHardenedConfigs = true;
            };
            givc.adminvm.enable = true;

            # Enable dynamic hostname export for VMs
            identity.vmHostNameExport.enable = true;

            # Storage
            storagevm = {
              enable = true;
              name = vmName;
              files = [
                "/etc/locale-givc.conf"
                "/etc/timezone.conf"
              ];
              directories = lib.mkIf globalConfig.storage.encryption.enable [
                "/var/lib/swtpm"
              ];
              encryption.enable = globalConfig.storage.encryption.enable;
            };

            # Networking
            virtualization.microvm.vm-networking = {
              enable = true;
              inherit vmName;
            };

            virtualization.microvm.tpm.passthrough = {
              inherit (globalConfig.storage.encryption) enable;
              rootNVIndex = "0x81701000";
            };

            # Logging - from globalConfig
            logging = {
              inherit (globalConfig.logging) enable listener;
              server = {
                inherit (globalConfig.logging) enable;
                endpoint = globalConfig.logging.server.endpoint or "";
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
              recovery.enable = true;
            };

            # GIVC configuration - from globalConfig
            givc = {
              inherit (globalConfig.givc) enable;
              inherit (globalConfig.givc) debug;
            };

            # Security
            security = {
              fail2ban.enable = globalConfig.development.ssh.daemon.enable;
              audit.enable = lib.mkDefault (globalConfig.security.audit.enable or false);
            };
          };

          system.stateVersion = lib.trivial.release;

          nixpkgs = {
            buildPlatform.system = globalConfig.platform.buildSystem;
            hostPlatform.system = globalConfig.platform.hostSystem;
          };

          microvm = {
            optimize.enable = false;
            hypervisor = "qemu";
            qemu = {
              extraArgs = [
                "-device"
                "vhost-vsock-pci,guest-cid=${toString (hostConfig.networking.thisVm.cid or 10)}"
              ];
            };

            shares = [
              {
                tag = "ghaf-common";
                source = "/persist/common";
                mountPoint = "/etc/common";
                proto = "virtiofs";
              }
            ]
            ++ lib.optionals (!globalConfig.storage.storeOnDisk) [
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
  cfg = config.ghaf.virtualization.microvm.adminvm;
in
{
  _file = ./adminvm.nix;

  options.ghaf.virtualization.microvm.adminvm = {
    enable = lib.mkEnableOption "AdminVM";

    evaluatedConfig = lib.mkOption {
      type = lib.types.nullOr lib.types.unspecified;
      default = null;
      description = ''
        Pre-evaluated Admin VM NixOS configuration.
        When set, this takes precedence over the legacy adminvmBaseConfiguration.
        Profiles should set this using adminvmBase from laptop-x86 profile.
      '';
    };

    extraModules = lib.mkOption {
      description = ''
        DEPRECATED: Use adminvm-features modules instead.
        List of additional modules to be imported and evaluated as part of
        AdminVM's NixOS configuration.
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
    # Warning if extraModules still used (deprecated)
    warnings = lib.optionals (cfg.extraModules != [ ]) [
      ''
        ghaf.virtualization.microvm.adminvm.extraModules is deprecated.
        Use adminvm-features modules instead, or set evaluatedConfig
        from config.ghaf.profiles.laptop-x86.adminvmBase.
      ''
    ];

    ghaf.common.extraNetworking.hosts.${vmName} = cfg.extraNetworking;

    microvm.vms."${vmName}" =
      if cfg.evaluatedConfig != null then
        # New path: Use pre-evaluated config from profile
        {
          autostart = true;
          inherit (inputs) nixpkgs;
          inherit (cfg) evaluatedConfig;
        }
      else
        # Legacy path: Build config inline (for non-laptop targets)
        {
          autostart = true;
          inherit (inputs) nixpkgs;
          specialArgs = lib.ghaf.vm.mkSpecialArgs {
            inherit lib inputs;
            globalConfig = hostGlobalConfig;
            hostConfig = lib.ghaf.vm.mkHostConfig {
              inherit config vmName;
            };
          };
          config = adminvmBaseConfiguration // {
            imports = adminvmBaseConfiguration.imports ++ cfg.extraModules;
          };
        };
  };
}
