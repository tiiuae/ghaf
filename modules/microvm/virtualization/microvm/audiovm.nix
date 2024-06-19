# Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  config,
  lib,
  ...
}: let
  configHost = config;
  vmName = "audio-vm";
  macAddress = "02:00:00:03:03:03";
  audiovmBaseConfiguration = {
    imports = [
      (import ./common/vm-networking.nix {
        inherit config lib vmName macAddress;
        internalIP = 5;
      })
      ({
        lib,
        pkgs,
        ...
      }: {
        imports = [
          ../../../common
        ];

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
            withNss = true;
            withResolved = true;
            withTimesyncd = true;
            withDebug = configHost.ghaf.profiles.debug.enable;
          };
          services.audio.enable = true;
        };

        environment = {
          systemPackages = [
            pkgs.pulseaudio
            pkgs.pamixer
            pkgs.pipewire
          ];
        };

        time.timeZone = config.time.timeZone;
        system.stateVersion = lib.trivial.release;

        nixpkgs = {
          buildPlatform.system = configHost.nixpkgs.buildPlatform.system;
          hostPlatform.system = configHost.nixpkgs.hostPlatform.system;
        };

        microvm = {
          optimize.enable = true;
          vcpu = 1;
          mem = 256;
          hypervisor = "qemu";
          shares = [
            {
              tag = "ro-store";
              source = "/nix/store";
              mountPoint = "/nix/.ro-store";
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
          };
        };

        # Fixed IP-address for debugging subnet
        systemd.network.networks."10-ethint0".addresses = let
          getAudioVmEntry = builtins.filter (x: x.name == "audio-vm-debug") config.ghaf.networking.hosts.entries;
          ip = lib.head (builtins.map (x: x.ip) getAudioVmEntry);
        in [
          {
            Address = "${ip}/24";
          }
        ];
      })
    ];
  };
  cfg = config.ghaf.virtualization.microvm.audiovm;
in {
  options.ghaf.virtualization.microvm.audiovm = {
    enable = lib.mkEnableOption "AudioVM";

    extraModules = lib.mkOption {
      description = ''
        List of additional modules to be imported and evaluated as part of
        AudioVM's NixOS configuration.
      '';
      default = [];
    };
  };

  config = lib.mkIf cfg.enable {
    microvm.vms."${vmName}" = {
      autostart = true;
      config =
        audiovmBaseConfiguration
        // {
          imports =
            audiovmBaseConfiguration.imports
            ++ cfg.extraModules;
        };
    };
  };
}
