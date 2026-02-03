# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# Admin VM Configuration Module
#
# Note: `inputs` is received via specialArgs from mkLaptopConfiguration.
# This module uses `globalConfig` for settings that propagate from host.
{
  config,
  lib,
  inputs,
  ...
}:
let
  # Use globalConfig for settings that should propagate from host
  # This replaces the old configHost pattern
  globalConfig = config.ghaf.global-config;

  vmName = "admin-vm";

  adminvmBaseConfiguration = {
    imports = [
      inputs.preservation.nixosModules.preservation
      inputs.self.nixosModules.givc
      inputs.self.nixosModules.hardware-x86_64-guest-kernel
      inputs.self.nixosModules.vm-modules
      inputs.self.nixosModules.profiles
      (
        { lib, ... }:
        {
          _file = ./adminvm.nix;

          ghaf = {
            # Profiles - use globalConfig for propagated settings
            profiles.debug.enable = lib.mkDefault globalConfig.debug.enable;
            development = {
              # NOTE: SSH port also becomes accessible on the network interface
              #       that has been passed through to VM
              ssh.daemon.enable = lib.mkDefault globalConfig.development.ssh.daemon.enable;
              debug.tools.enable = lib.mkDefault globalConfig.development.debug.tools.enable;
              nix-setup.enable = lib.mkDefault globalConfig.development.nix-setup.enable;
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

            # Services
            logging = {
              inherit (configHost.ghaf.logging) enable;
              server = {
                inherit (globalConfig.logging) enable;
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

            security.fail2ban.enable = globalConfig.development.ssh.daemon.enable;

          };

          system.stateVersion = lib.trivial.release;

          nixpkgs = {
            buildPlatform.system = globalConfig.platform.buildSystem;
            hostPlatform.system = globalConfig.platform.hostSystem;
          };

          microvm = {
            optimize.enable = false;
            #TODO: Add back support cloud-hypervisor
            #the system fails to switch root to the stage2 with cloud-hypervisor
            hypervisor = "qemu";
            qemu = {
              extraArgs = [
                "-device"
                "vhost-vsock-pci,guest-cid=${toString config.ghaf.networking.hosts.${vmName}.cid}"
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
            # Shared store (when not using storeOnDisk)
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

    extraModules = lib.mkOption {
      description = ''
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
    ghaf.common.extraNetworking.hosts.${vmName} = cfg.extraNetworking;

    microvm.vms."${vmName}" = {
      autostart = true;
      inherit (inputs) nixpkgs;
      # Pass globalConfig to VM via specialArgs for consistent propagation
      specialArgs = lib.ghaf.mkVmSpecialArgs {
        inherit lib inputs globalConfig;
      };
      config = adminvmBaseConfiguration // {
        imports = adminvmBaseConfiguration.imports ++ cfg.extraModules;
      };
    };
  };
}
