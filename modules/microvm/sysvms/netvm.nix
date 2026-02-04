# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# Net VM Configuration Module
#
# This module uses the globalConfig pattern:
# - Global settings (debug, development, logging, storage) come via globalConfig specialArg
# - Host-specific settings (networking.hosts) come via hostConfig specialArg
#
# The VM configuration is self-contained and does not reference `configHost`.
{
  config,
  lib,
  inputs,
  ...
}:
let
  vmName = "net-vm";
  hostGlobalConfig = config.ghaf.global-config;

  netvmBaseConfiguration = {
    _file = ./netvm.nix;
    imports = [
      inputs.preservation.nixosModules.preservation
      inputs.self.nixosModules.givc
      inputs.self.nixosModules.hardware-x86_64-guest-kernel
      inputs.self.nixosModules.vm-modules
      inputs.self.nixosModules.profiles
      (
        {
          lib,
          pkgs,
          globalConfig,
          hostConfig,
          ...
        }:
        {
          ghaf = {
            # Profiles - from globalConfig
            profiles.debug.enable = lib.mkDefault globalConfig.debug.enable;
            development = {
              # NOTE: SSH port also becomes accessible on the network interface
              #       that has been passed through to NetVM
              ssh.daemon.enable = lib.mkDefault globalConfig.development.ssh.daemon.enable;
              debug.tools.enable = lib.mkDefault globalConfig.development.debug.tools.enable;
              debug.tools.net.enable = lib.mkDefault globalConfig.development.debug.tools.enable;
              nix-setup.enable = lib.mkDefault globalConfig.development.nix-setup.enable;
            };
            users = {
              proxyUser = {
                enable = true;
                extraGroups = [
                  "networkmanager"
                ];
              };
            };

            # Enable dynamic hostname export and setter for NetVM
            identity.vmHostNameExport.enable = true;
            identity.vmHostNameSetter.enable = true;

            # System
            type = "system-vm";
            systemd = {
              enable = true;
              withName = "netvm-systemd";
              withLocaled = true;
              withPolkit = true;
              withResolved = true;
              withTimesyncd = true;
              withDebug = globalConfig.debug.enable;
              withHardenedConfigs = true;
            };
            givc.netvm.enable = true;

            # Storage - from globalConfig
            storagevm = {
              enable = true;
              name = vmName;
              encryption.enable = globalConfig.storage.encryption.enable;
            };

            # Networking
            virtualization.microvm.vm-networking = {
              enable = true;
              isGateway = true;
              inherit vmName;
            };

            virtualization.microvm.tpm.passthrough = {
              # At the moment the TPM is only used for storage encryption, so the features are coupled.
              inherit (globalConfig.storage.encryption) enable;
              rootNVIndex = "0x81704000";
            };

            # Services
            services = {
              power-manager.vm = {
                enable = pkgs.stdenv.hostPlatform.isx86;
                pciSuspendServices = [
                  "NetworkManager.service"
                  "wpa_supplicant.service"
                ];
              };

              performance = {
                net.enable = true;
              };
            };
            logging = {
              inherit (globalConfig.logging) enable listener;
              client.enable = globalConfig.logging.enable;
            };

            security = {
              fail2ban.enable = globalConfig.development.ssh.daemon.enable;
              ssh-tarpit = {
                inherit (globalConfig.development.ssh.daemon) enable;
                listenAddress = hostConfig.networking.thisVm.ipv4;
              };
            };
          };

          time.timeZone = globalConfig.platform.timeZone;
          system.stateVersion = lib.trivial.release;

          nixpkgs = {
            buildPlatform.system = globalConfig.platform.buildSystem;
            hostPlatform.system = globalConfig.platform.hostSystem;
          };

          ghaf.firewall =
            let
              dnsPort = 53;
            in
            {
              allowedTCPPorts = [ dnsPort ];
              allowedUDPPorts = [ dnsPort ];
            };

          microvm = {
            # Optimize is disabled because when it is enabled, qemu is built without libusb
            optimize.enable = false;
            hypervisor = "qemu";

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

            qemu = {
              machine =
                {
                  # Use the same machine type as the host
                  x86_64-linux = "q35";
                  aarch64-linux = "virt";
                }
                .${globalConfig.platform.hostSystem};
              extraArgs = [
                "-device"
                "qemu-xhci"
              ];
            };
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
  cfg = config.ghaf.virtualization.microvm.netvm;
in
{
  options.ghaf.virtualization.microvm.netvm = {
    enable = lib.mkEnableOption "NetVM";

    evaluatedConfig = lib.mkOption {
      type = lib.types.nullOr lib.types.unspecified;
      default = null;
      description = ''
        Pre-evaluated NixOS configuration for Net VM.

        When set, this configuration is used directly instead of building
        the VM config inline. This enables the composition model where
        profiles can extend a base configuration.

        Example:
          netvm.evaluatedConfig = config.ghaf.profiles.laptop-x86.netvmBase;
          # Or with extensions:
          netvm.evaluatedConfig = config.ghaf.profiles.laptop-x86.netvmBase.extendModules {
            modules = config.ghaf.hardware.definition.netvm.extraModules;
          };
      '';
    };

    extraModules = lib.mkOption {
      description = ''
        List of additional modules to be imported and evaluated as part of
        NetVM's NixOS configuration.

        NOTE: For laptop targets using evaluatedConfig, platform-specific
        modules should go through hardware.definition.netvm.extraModules.
        This option is primarily for non-laptop platforms (Jetson, etc.)
        that don't use the laptop-x86 profile.
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

    microvm.vms."${vmName}" =
      if cfg.evaluatedConfig != null then
        # New path: Use pre-evaluated config from profile
        # This is the recommended approach for laptop targets
        {
          autostart = !config.ghaf.microvm-boot.enable;
          restartIfChanged = false;
          inherit (inputs) nixpkgs;
          inherit (cfg) evaluatedConfig;
        }
      else
        # Legacy path: Build config inline
        # Used by Jetson and other non-laptop targets that don't have laptop-x86 profile
        {
          autostart = !config.ghaf.microvm-boot.enable;
          restartIfChanged = false;
          inherit (inputs) nixpkgs;
          specialArgs = lib.ghaf.mkVmSpecialArgs {
            inherit lib inputs;
            globalConfig = hostGlobalConfig;
            hostConfig = lib.ghaf.mkVmHostConfig {
              inherit config vmName;
            };
          };

          config = netvmBaseConfiguration // {
            imports = netvmBaseConfiguration.imports ++ cfg.extraModules;
          };
        };
  };

}
