# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{ inputs }:
{
  config,
  lib,
  ...
}:
let
  configHost = config;
  vmName = "audio-vm";

  audiovmBaseConfiguration = {
    imports = [
      inputs.preservation.nixosModules.preservation
      inputs.self.nixosModules.givc
      inputs.self.nixosModules.hardware-x86_64-guest-kernel
      inputs.self.nixosModules.vm-modules
      inputs.self.nixosModules.profiles
      (
        { lib, pkgs, ... }:
        {
          ghaf = {
            # Profiles
            profiles.debug.enable = lib.mkDefault configHost.ghaf.profiles.debug.enable;
            development = {
              ssh.daemon.enable = lib.mkDefault configHost.ghaf.development.ssh.daemon.enable;
              debug.tools.enable = lib.mkDefault configHost.ghaf.development.debug.tools.enable;
              nix-setup.enable = lib.mkDefault configHost.ghaf.development.nix-setup.enable;
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
              withDebug = configHost.ghaf.profiles.debug.enable;
              withHardenedConfigs = true;
            };
            givc.audiovm.enable = true;

            # Enable dynamic hostname export for VMs
            identity.vmHostNameExport.enable = true;

            # Storage
            storagevm = {
              enable = true;
              name = vmName;
              encryption.enable = configHost.ghaf.virtualization.storagevm-encryption.enable;
            };
            # Networking
            virtualization.microvm.vm-networking = {
              enable = true;
              inherit vmName;
            };
            virtualization.microvm.tpm.passthrough = {
              inherit (configHost.ghaf.virtualization.storagevm-encryption) enable;
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
              inherit (configHost.ghaf.logging) enable;
              client.enable = configHost.ghaf.logging.enable;
            };

            security.fail2ban.enable = configHost.ghaf.development.ssh.daemon.enable;

          };

          environment = {
            systemPackages = [
              pkgs.pulseaudio
              pkgs.pamixer
              pkgs.pipewire
            ]
            ++ lib.optional config.ghaf.development.debug.tools.enable pkgs.alsa-utils;
          };

          time.timeZone = config.time.timeZone;
          system.stateVersion = lib.trivial.release;

          nixpkgs = {
            buildPlatform.system = configHost.nixpkgs.buildPlatform.system;
            hostPlatform.system = configHost.nixpkgs.hostPlatform.system;
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
            ++ lib.optionals (!configHost.ghaf.virtualization.microvm.storeOnDisk) [
              {
                tag = "ro-store";
                source = "/nix/store";
                mountPoint = "/nix/.ro-store";
                proto = "virtiofs";
              }
            ];

            writableStoreOverlay = lib.mkIf (
              !configHost.ghaf.virtualization.microvm.storeOnDisk
            ) "/nix/.rw-store";

            qemu = {
              machine =
                {
                  # Use the same machine type as the host
                  x86_64-linux = "q35";
                  aarch64-linux = "virt";
                }
                .${configHost.nixpkgs.hostPlatform.system};
              extraArgs = [
                "-device"
                "qemu-xhci"
              ];
            };
          }
          // lib.optionalAttrs configHost.ghaf.virtualization.microvm.storeOnDisk {
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

    extraModules = lib.mkOption {
      description = ''
        List of additional modules to be imported and evaluated as part of
        AudioVM's NixOS configuration.
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
      autostart = !config.ghaf.microvm-boot.enable;
      inherit (inputs) nixpkgs;
      specialArgs = { inherit lib; };

      config = audiovmBaseConfiguration // {
        imports = audiovmBaseConfiguration.imports ++ cfg.extraModules;
      };
    };
  };
}
