# Copyright 2022-2023 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  config,
  lib,
  pkgs,
  ...
}: let
  configHost = config;
  vmName = "audio-vm";
  macAddress = "02:00:00:02:03:04";
  audiovmBaseConfiguration = {
    imports = [
      (import ./common/vm-networking.nix {inherit vmName macAddress;})
      ({
        lib,
        pkgs,
        ...
      }: {
        ghaf = {
          users.accounts.enable = lib.mkDefault configHost.ghaf.users.accounts.enable;
          profiles.graphics.enable = false;
          development = {
            ssh.daemon.enable = lib.mkDefault configHost.ghaf.development.ssh.daemon.enable;
            debug.tools.enable = lib.mkDefault configHost.ghaf.development.debug.tools.enable;
          };
        };

        environment = {
          systemPackages = [
            pkgs.pamixer
          ];
        };

        system.stateVersion = lib.trivial.release;

        nixpkgs.buildPlatform.system = configHost.nixpkgs.buildPlatform.system;
        nixpkgs.hostPlatform.system = configHost.nixpkgs.hostPlatform.system;

        time.timeZone = "Asia/Dubai";

        # Enable pulseaudio support for host as a service
        sound.enable = true;
        hardware.pulseaudio.enable = true;
        hardware.pulseaudio.systemWide = true;
#        networking.firewall.interfaces.virbr0.allowedTCPPorts = [4713];
        networking.firewall.allowedTCPPorts = [4713];

        # Allow microvm user to access pulseaudio
        users.extraUsers.ghaf.extraGroups = ["audio" "pulse-access"];
        # Enable and allow TCP connection from localhost only
        hardware.pulseaudio.tcp.enable = true;
        hardware.pulseaudio.tcp.anonymousClients.allowedIpRanges = ["127.0.0.1" "192.168.101.2" "192.168.101.3"];
        hardware.pulseaudio.extraConfig = ''
            load-module module-native-protocol-unix
            load-module module-native-protocol-tcp auth-ip-acl=127.0.0.1;192.168.101.2;192.168.101.3
            set-sink-volume @DEFAULT_SINK@ 60000
        '';

        microvm = {
          optimize.enable = false;
          vcpu = 1;
          mem = 1024;
          hypervisor = "qemu";
          shares = [
            {
              tag = "rw-waypipe-ssh-public-key";
              source = "/run/waypipe-ssh-public-key";
              mountPoint = "/run/waypipe-ssh-public-key";
            }
            {
              tag = "ro-store";
              source = "/nix/store";
              mountPoint = "/nix/.ro-store";
            }
          ];
          writableStoreOverlay = lib.mkIf config.ghaf.development.debug.tools.enable "/nix/.rw-store";

          qemu.extraArgs = [
          ];
        };

        imports = import ../../module-list.nix;

        # Fixed IP-address for debugging subnet
        systemd.network.networks."10-ethint0".addresses = [
          {
            addressConfig.Address = "192.168.101.4/24";
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
      specialArgs = {inherit lib;};
    };
  };
}
