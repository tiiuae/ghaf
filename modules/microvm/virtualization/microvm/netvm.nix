# Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  config,
  lib,
  pkgs,
  ...
}: let
  configHost = config;
  vmName = "net-vm";
  macAddress = "02:00:00:01:01:01";

  isGuiVmEnabled = config.ghaf.virtualization.microvm.guivm.enable;

  sshKeysHelper = pkgs.callPackage ../../../../packages/ssh-keys-helper {
    inherit pkgs;
    inherit config;
  };

  netvmBaseConfiguration = {
    imports = [
      (import ./common/vm-networking.nix {
        inherit config lib vmName macAddress;
        internalIP = 1;
        gateway = [];
      })
      ({lib, ...}: {
        ghaf = {
          users.accounts.enable = lib.mkDefault configHost.ghaf.users.accounts.enable;
          profiles.debug.enable = lib.mkDefault configHost.ghaf.profiles.debug.enable;
          development = {
            # NOTE: SSH port also becomes accessible on the network interface
            #       that has been passed through to NetVM
            ssh.daemon.enable = lib.mkDefault configHost.ghaf.development.ssh.daemon.enable;
            debug.tools.enable = lib.mkDefault configHost.ghaf.development.debug.tools.enable;
            nix-setup.enable = lib.mkDefault configHost.ghaf.development.nix-setup.enable;
          };
          systemd = {
            enable = true;
            withName = "netvm-systemd";
            withPolkit = true;
            withResolved = true;
            withDebug = configHost.ghaf.profiles.debug.enable;
            withHardenedConfigs = true;
          };
        };

        system.stateVersion = lib.trivial.release;

        nixpkgs = {
          buildPlatform.system = configHost.nixpkgs.buildPlatform.system;
          hostPlatform.system = configHost.nixpkgs.hostPlatform.system;
        };

        networking = {
          firewall.allowedTCPPorts = [53];
          firewall.allowedUDPPorts = [53];
        };

        # Add simple wi-fi connection helper
        environment.systemPackages = lib.mkIf config.ghaf.profiles.debug.enable [pkgs.wifi-connector];

        microvm = {
          optimize.enable = true;
          hypervisor = "qemu";
          shares =
            [
              {
                tag = "ro-store";
                source = "/nix/store";
                mountPoint = "/nix/.ro-store";
              }
            ]
            ++ lib.optionals isGuiVmEnabled [
              {
                # Add the waypipe-ssh public key to the microvm
                tag = configHost.ghaf.security.sshKeys.waypipeSshPublicKeyName;
                source = configHost.ghaf.security.sshKeys.waypipeSshPublicKeyDir;
                mountPoint = configHost.ghaf.security.sshKeys.waypipeSshPublicKeyDir;
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

        fileSystems = lib.mkIf isGuiVmEnabled {${configHost.ghaf.security.sshKeys.waypipeSshPublicKeyDir}.options = ["ro"];};

        # SSH is very picky about to file permissions and ownership and will
        # accept neither direct path inside /nix/store or symlink that points
        # there. Therefore we copy the file to /etc/ssh/get-auth-keys (by
        # setting mode), instead of symlinking it.
        environment.etc = lib.mkIf isGuiVmEnabled {${configHost.ghaf.security.sshKeys.getAuthKeysFilePathInEtc} = sshKeysHelper.getAuthKeysSource;};

        imports = [../../../common];
      })
    ];
  };
  cfg = config.ghaf.virtualization.microvm.netvm;
in {
  options.ghaf.virtualization.microvm.netvm = {
    enable = lib.mkEnableOption "NetVM";

    extraModules = lib.mkOption {
      description = ''
        List of additional modules to be imported and evaluated as part of
        NetVM's NixOS configuration.
      '';
      default = [];
    };
  };

  config = lib.mkIf cfg.enable {
    microvm.vms."${vmName}" = {
      autostart = true;
      restartIfChanged = false;
      config =
        netvmBaseConfiguration
        // {
          imports =
            netvmBaseConfiguration.imports
            ++ cfg.extraModules;
        };
    };
  };
}
