# Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
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
      inputs.impermanence.nixosModules.impermanence
      inputs.self.nixosModules.givc
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
              ];
            };

            # System
            type = "system-vm";
            systemd = {
              enable = true;
              withName = "audiovm-systemd";
              withAudit = configHost.ghaf.profiles.debug.enable;
              withAudio = true;
              withBluetooth = true;
              withNss = true;
              withResolved = true;
              withTimesyncd = true;
              withDebug = configHost.ghaf.profiles.debug.enable;
              withHardenedConfigs = true;
            };
            givc.audiovm.enable = true;

            # Storage
            storagevm = {
              enable = true;
              name = vmName;
            };

            # Services
            services.audio.enable = true;
            logging.client.enable = configHost.ghaf.logging.enable;
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

          microvm = {
            # Optimize is disabled because when it is enabled, qemu is built without libusb
            optimize.enable = false;
            vcpu = 2;
            mem = 384;
            hypervisor = "qemu";
            shares = [
              {
                tag = "ro-store";
                source = "/nix/store";
                mountPoint = "/nix/.ro-store";
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
              ];
            };
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
      type =
        let
          extraNetworkingType = import ../../common/networking/common_types.nix { inherit lib; };
        in
        extraNetworkingType;
      description = "Extra Networking option";
      default = { };
    };
  };

  config = lib.mkIf cfg.enable {

    ghaf.common.extraNetworking.hosts.audio-vm = cfg.extraNetworking;

    microvm.vms."${vmName}" = {
      autostart = true;
      inherit (inputs) nixpkgs;
      config = audiovmBaseConfiguration // {
        imports = audiovmBaseConfiguration.imports ++ cfg.extraModules;
        # Networking
        ghaf.virtualization.microvm.vm-networking =
          {
            enable = true;
            inherit vmName;
          }
          // lib.optionalAttrs ((cfg.extraNetworking.interfaceName or null) != null) {
            inherit (cfg.extraNetworking) interfaceName;
          };

      };
    };
  };
}
