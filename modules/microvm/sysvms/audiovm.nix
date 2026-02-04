# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# Audio VM Configuration Module
#
# This module uses the globalConfig pattern:
# - Global settings (debug, development, logging, storage) come via globalConfig specialArg
# - Host-specific settings (platform, boot) come via globalConfig.platform
#
# The VM configuration is self-contained and does not reference `configHost`.
{
  config,
  lib,
  inputs,
  ...
}:
let
  vmName = "audio-vm";
  hostGlobalConfig = config.ghaf.global-config;

  audiovmBaseConfiguration = {
    _file = ./audiovm.nix;
    imports = [
      inputs.preservation.nixosModules.preservation
      inputs.self.nixosModules.givc
      inputs.self.nixosModules.hardware-x86_64-guest-kernel
      inputs.self.nixosModules.vm-modules
      inputs.self.nixosModules.profiles
      (
        {
          config,
          lib,
          pkgs,
          globalConfig,
          ...
        }:
        {
          ghaf = {
            # Profiles - from globalConfig
            profiles.debug.enable = lib.mkDefault globalConfig.debug.enable;
            development = {
              ssh.daemon.enable = lib.mkDefault globalConfig.development.ssh.daemon.enable;
              debug.tools.enable = lib.mkDefault globalConfig.development.debug.tools.enable;
              nix-setup.enable = lib.mkDefault globalConfig.development.nix-setup.enable;
            };
            users.proxyUser = {
              enable = true;
              extraGroups = [
                "audio"
                "pipewire"
                "bluetooth"
              ];
            };

            # System
            type = "system-vm";
            systemd = {
              enable = true;
              withName = "audiovm-systemd";
              withLocaled = true;
              withAudio = true;
              withBluetooth = true;
              withNss = true;
              withResolved = true;
              withTimesyncd = true;
              withDebug = globalConfig.debug.enable;
              withHardenedConfigs = true;
            };
            givc.audiovm.enable = true;

            # Enable dynamic hostname export for VMs
            identity.vmHostNameExport.enable = true;

            # Storage - from globalConfig
            storagevm = {
              enable = true;
              name = vmName;
              encryption.enable = globalConfig.storage.encryption.enable;
            };
            # Networking
            virtualization.microvm.vm-networking = {
              enable = true;
              inherit vmName;
            };
            virtualization.microvm.tpm.passthrough = {
              inherit (globalConfig.storage.encryption) enable;
              rootNVIndex = "0x81702000";
            };
            # Services
            services = {
              audio = {
                enable = true;
                role = "server";
                server.pipewireForwarding.enable = true;
              };
              power-manager.vm = {
                enable = true;
                pciSuspendServices = [
                  "pipewire.socket"
                  "pipewire.service"
                  "bluetooth.service"
                ];
              };
              performance.vm = {
                enable = true;
              };
            };
            logging = {
              inherit (globalConfig.logging) enable listener;
              client.enable = globalConfig.logging.enable;
            };

            security.fail2ban.enable = globalConfig.development.ssh.daemon.enable;

          };

          environment = {
            systemPackages = [
              pkgs.pulseaudio
              pkgs.pamixer
              pkgs.pipewire
            ]
            ++ lib.optional config.ghaf.development.debug.tools.enable pkgs.alsa-utils;
          };

          time.timeZone = globalConfig.platform.timeZone;
          system.stateVersion = lib.trivial.release;

          nixpkgs = {
            buildPlatform.system = globalConfig.platform.buildSystem;
            hostPlatform.system = globalConfig.platform.hostSystem;
          };

          microvm = {
            # Optimize is disabled because when it is enabled, qemu is built without libusb
            optimize.enable = false;
            vcpu = 2;
            mem = 384;
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
  cfg = config.ghaf.virtualization.microvm.audiovm;
in
{
  options.ghaf.virtualization.microvm.audiovm = {
    enable = lib.mkEnableOption "AudioVM";

    evaluatedConfig = lib.mkOption {
      type = lib.types.nullOr lib.types.unspecified;
      default = null;
      description = ''
        Pre-evaluated NixOS configuration for Audio VM.
        When set (by profiles like mvp-user-trial), uses this instead of building inline.
        This enables the layered composition pattern with extendModules.
      '';
    };

    extraModules = lib.mkOption {
      description = ''
        List of additional modules to be imported and evaluated as part of
        AudioVM's NixOS configuration.

        DEPRECATED: This option is deprecated. Use the evaluatedConfig pattern instead:
          ghaf.virtualization.microvm.audiovm.evaluatedConfig =
            config.ghaf.profiles.laptop-x86.audiovmBase.extendModules { modules = [...]; };
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
      ghaf.virtualization.microvm.audiovm.extraModules is deprecated.
      Please migrate to the evaluatedConfig pattern using audiovm-base.nix.
      See modules/microvm/sysvms/audiovm-base.nix for the new approach.
    '';

    microvm.vms."${vmName}" =
      if cfg.evaluatedConfig != null then
        # New path: Use pre-evaluated config from profile
        # This is the recommended approach for laptop targets
        {
          autostart = !config.ghaf.microvm-boot.enable;
          inherit (inputs) nixpkgs;
          inherit (cfg) evaluatedConfig;
        }
      else
        # Legacy path: Build config inline
        # Used by non-laptop targets (Jetson, etc.) that don't have laptop-x86 profile
        {
          autostart = !config.ghaf.microvm-boot.enable;
          inherit (inputs) nixpkgs;
          specialArgs = lib.ghaf.mkVmSpecialArgs {
            inherit lib inputs;
            globalConfig = hostGlobalConfig;
          };

          config = audiovmBaseConfiguration // {
            imports = audiovmBaseConfiguration.imports ++ cfg.extraModules;
          };
        };
  };
}
