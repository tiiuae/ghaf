# Copyright 2022-2023 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  config,
  lib,
  ...
}: let
  configHost = config;
  cfg = config.ghaf.virtualization.microvm.appvm;
  makeVm = {
    vm,
    index,
  }: let
    vmName = "${vm.name}-vm";
    cid =
      if vm.cid > 0
      then vm.cid
      else cfg.vsockBaseCID + index;
    appvmConfiguration = {
      imports = [
        (import ./common/vm-networking.nix {
          inherit vmName;
          inherit (vm) macAddress;
        })
        ({
          lib,
          config,
          pkgs,
          ...
        }: {
          ghaf = {
            users.accounts.enable = lib.mkDefault configHost.ghaf.users.accounts.enable;

            # Don't enable Wayland compositor inside every AppVM
            profiles.graphics.enable = false;

            development = {
              ssh.daemon.enable = lib.mkDefault configHost.ghaf.development.ssh.daemon.enable;
              debug.tools.enable = lib.mkDefault configHost.ghaf.development.debug.tools.enable;
            };
          };

          # SSH is very picky about the file permissions and ownership and will
          # accept neither direct path inside /nix/store or symlink that points
          # there. Therefore we copy the file to /etc/ssh/get-auth-keys (by
          # setting mode), instead of symlinking it.
          environment.etc."ssh/get-auth-keys" = {
            source = let
              script = pkgs.writeShellScriptBin "get-auth-keys" ''
                [[ "$1" != "ghaf" ]] && exit 0
                ${pkgs.coreutils}/bin/cat /run/waypipe-ssh-public-key/id_ed25519.pub
              '';
            in "${script}/bin/get-auth-keys";
            mode = "0555";
          };
          services.openssh = {
            authorizedKeysCommand = "/etc/ssh/get-auth-keys";
            authorizedKeysCommandUser = "nobody";
          };

          system.stateVersion = lib.trivial.release;

          nixpkgs.buildPlatform.system = configHost.nixpkgs.buildPlatform.system;
          nixpkgs.hostPlatform.system = configHost.nixpkgs.hostPlatform.system;

          time.timeZone = "Asia/Dubai";

          environment.systemPackages = [
            pkgs.waypipe
          ];

          microvm = {
            optimize.enable = false;
            mem = vm.ramMb;
            vcpu = vm.cores;
            hypervisor = "qemu";
            shares = [
              {
                tag = "waypipe-ssh-public-key";
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
              "-M"
              "q35,accel=kvm:tcg,mem-merge=on,sata=off"
              "-device"
              "vhost-vsock-pci,guest-cid=${toString cid}"
            ];
          };
          fileSystems."/run/waypipe-ssh-public-key".options = ["ro"];

          imports = import ../../module-list.nix;
        })
      ];
    };
  in {
    autostart = true;
    config = appvmConfiguration // {imports = appvmConfiguration.imports ++ cfg.extraModules ++ vm.extraModules ++ [{environment.systemPackages = vm.packages;}];};
    specialArgs = {inherit lib;};
  };
in {
  options.ghaf.virtualization.microvm.appvm = with lib; {
    enable = lib.mkEnableOption "appvm";
    vms = with types;
      mkOption {
        description = ''
          List of AppVMs to be created
        '';
        type = lib.types.listOf (submodule {
          options = {
            name = mkOption {
              description = ''
                Name of the AppVM
              '';
              type = str;
            };
            packages = mkOption {
              description = ''
                Packages that are included into the AppVM
              '';
              type = types.listOf package;
              default = [];
            };
            macAddress = mkOption {
              description = ''
                AppVM's network interface MAC address
              '';
              type = str;
            };
            ramMb = mkOption {
              description = ''
                Amount of RAM for this AppVM
              '';
              type = int;
            };
            cores = mkOption {
              description = ''
                Amount of processor cores for this AppVM
              '';
              type = int;
            };
            extraModules = mkOption {
              description = ''
                List of additional modules to be imported and evaluated as part of
                appvm's NixOS configuration.
              '';
              default = [];
            };
            cid = mkOption {
              description = ''
                VSOCK context identifier (CID) for the AppVM
                Default value 0 means auto-assign using vsockBaseCID and AppVM index
              '';
              type = int;
              default = 0;
            };
          };
        });
        default = [];
      };

    extraModules = mkOption {
      description = ''
        List of additional modules to be imported and evaluated as part of
        appvm's NixOS configuration.
      '';
      default = [];
    };

    # Base VSOCK CID which is used for auto assigning CIDs for all AppVMs
    # For example, when it's set to 100, AppVMs will get 100, 101, 102, etc.
    # It is also possible to override the auto assinged CID using the vms.cid option
    vsockBaseCID = lib.mkOption {
      type = lib.types.int;
      default = 100;
      description = ''
        Context Identifier (CID) of the AppVM VSOCK
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    microvm.vms = let
      vms = lib.imap0 (index: vm: {"${vm.name}-vm" = makeVm {inherit index vm;};}) cfg.vms;
    in
      lib.foldr lib.recursiveUpdate {} vms;
  };
}
