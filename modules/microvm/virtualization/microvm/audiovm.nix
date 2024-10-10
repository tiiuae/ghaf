# Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{ inputs }:
{
  config,
  lib,
  pkgs,
  ...
}:
let
  configHost = config;
  vmName = "audio-vm";
  macAddress = "02:00:00:03:03:03";
  isGuiVmEnabled = config.ghaf.virtualization.microvm.guivm.enable;

  sshKeysHelper = pkgs.callPackage ../../../../packages/ssh-keys-helper {
    inherit pkgs;
    inherit config;
  };

  audiovmBaseConfiguration = {
    imports = [
      inputs.self.nixosModules.givc-audiovm
      inputs.impermanence.nixosModules.impermanence
      (import ./common/vm-networking.nix {
        inherit
          config
          lib
          vmName
          macAddress
          ;
        internalIP = 5;
      })
      ./common/storagevm.nix
      ../../../common/logging/client.nix
      (
        { lib, pkgs, ... }:
        {
          imports = [ ../../../common ];

          ghaf = {
            users.accounts.enable = lib.mkDefault configHost.ghaf.users.accounts.enable;
            profiles.debug.enable = lib.mkDefault configHost.ghaf.profiles.debug.enable;

            development = {
              ssh.daemon.enable = lib.mkDefault configHost.ghaf.development.ssh.daemon.enable;
              debug.tools.enable = lib.mkDefault configHost.ghaf.development.debug.tools.enable;
              nix-setup.enable = lib.mkDefault configHost.ghaf.development.nix-setup.enable;
            };
            systemd = {
              enable = true;
              withName = "audiovm-systemd";
              withAudit = configHost.ghaf.profiles.debug.enable;
              withNss = true;
              withResolved = true;
              withTimesyncd = true;
              withDebug = configHost.ghaf.profiles.debug.enable;
              withHardenedConfigs = true;
            };
            givc.audiovm.enable = true;
            services.audio.enable = true;
            # Logging client configuration
            logging.client.enable = configHost.ghaf.logging.client.enable;
            logging.client.endpoint = configHost.ghaf.logging.client.endpoint;
            storagevm = {
              enable = true;
              name = "audiovm";
            };
          };

          environment = {
            systemPackages = [
              pkgs.pulseaudio
              pkgs.pamixer
              pkgs.pipewire
            ] ++ lib.optional config.ghaf.development.debug.tools.enable pkgs.alsa-utils;
          };

          time.timeZone = config.time.timeZone;
          system.stateVersion = lib.trivial.release;

          nixpkgs = {
            buildPlatform.system = configHost.nixpkgs.buildPlatform.system;
            hostPlatform.system = configHost.nixpkgs.hostPlatform.system;
          };

          services.openssh = config.ghaf.security.sshKeys.sshAuthorizedKeysCommand;

          microvm = {
            # Optimize is disabled because when it is enabled, qemu is built without libusb
            optimize.enable = false;
            vcpu = 2;
            mem = 384;
            hypervisor = "qemu";
            shares =
              [
                {
                  tag = "ro-store";
                  source = "/nix/store";
                  mountPoint = "/nix/.ro-store";
                  proto = "virtiofs";
                }
              ]
              ++ lib.optionals isGuiVmEnabled [
                {
                  # Add the waypipe-ssh public key to the microvm
                  tag = config.ghaf.security.sshKeys.waypipeSshPublicKeyName;
                  source = config.ghaf.security.sshKeys.waypipeSshPublicKeyDir;
                  mountPoint = config.ghaf.security.sshKeys.waypipeSshPublicKeyDir;
                  proto = "virtiofs";
                }
              ];
            writableStoreOverlay = lib.mkIf config.ghaf.development.debug.tools.enable "/nix/.rw-store";
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
                "-acpitable"
                "file=/sys/firmware/acpi/tables/NHLT"
              ];
            };
          };

          fileSystems = lib.mkIf isGuiVmEnabled {
            ${config.ghaf.security.sshKeys.waypipeSshPublicKeyDir}.options = [ "ro" ];
          };

          # SSH is very picky about to file permissions and ownership and will
          # accept neither direct path inside /nix/store or symlink that points
          # there. Therefore we copy the file to /etc/ssh/get-auth-keys (by
          # setting mode), instead of symlinking it.
          environment.etc = lib.mkIf isGuiVmEnabled {
            ${config.ghaf.security.sshKeys.getAuthKeysFilePathInEtc} = sshKeysHelper.getAuthKeysSource;
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
  };

  config = lib.mkIf cfg.enable {
    microvm.vms."${vmName}" = {
      autostart = true;
      config = audiovmBaseConfiguration // {
        imports = audiovmBaseConfiguration.imports ++ cfg.extraModules;
      };
    };
  };
}
