# Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  config,
  lib,
  pkgs,
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
    memsocket = pkgs.callPackage ../../../user-apps/memsocket {
      debug = false; vms = config.ghaf.profiles.applications.ivShMemServer.vmCount;
    };
    memtest = pkgs.callPackage ../../../user-apps/memsocket/memtest.nix {};
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
        }: let
          waypipeBorder =
            if vm.borderColor != null
            then "--border \"${vm.borderColor}\""
            else "";
          runWaypipe = with pkgs;
            writeScriptBin "run-waypipe" ''
              #!${runtimeShell} -e
              ${pkgs.waypipe}/bin/waypipe -s ${config.ghaf.profiles.applications.ivShMemServer.serverSocketPath} ${waypipeBorder} server $@
            '';
        in {
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

          environment.systemPackages = [
            pkgs.waypipe
            runWaypipe
            memsocket
            memtest
            pkgs.perf-tools pkgs.linuxPackages.perf pkgs.socat
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
            ];
          };

          services.udev.extraRules = ''
            SUBSYSTEM=="misc",KERNEL=="ivshmem",GROUP="kvm",MODE="0666"
          '';

          systemd.user.services.memsocket = {
            enable = true;
            description = "memsocket";
            serviceConfig = {
              Type = "simple";
              ExecStart = "${memsocket}/bin/memsocket -s ${config.ghaf.profiles.applications.ivShMemServer.serverSocketPath} ${builtins.toString cid}";
              Restart = "always";
              RestartSec = "1";
            };
            wantedBy = ["default.target"];
          };

          fileSystems."/run/waypipe-ssh-public-key".options = ["ro"];

          imports = import ../../module-list.nix;
        })
      ];
    };
  in {
    autostart = true;
    config = appvmConfiguration // {imports = appvmConfiguration.imports ++ cfg.extraModules ++ vm.extraModules ++ [{environment.systemPackages = vm.packages;}];
    } // {
      boot.kernelPatches = [{
        name = "Shared memory PCI driver";
        patch = pkgs.fetchpatch {
          url = "https://raw.githubusercontent.com/tiiuae/shmsockproxy/dev/0001-ivshmem-driver.patch";
          sha256 = "sha256-SBeVxHqoyZNa7Q4iLfJbppqHQyygKGRJjtJGHh04DZA=";
        };
        extraConfig = ''
          KVM_IVSHMEM_VM_COUNT ${toString config.ghaf.profiles.applications.ivShMemServer.vmCount}
          '';
      }];
    };
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
            borderColor = mkOption {
              description = ''
                Border color of the AppVM window
              '';
              type = nullOr str;
              default = null;
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
    # For example, when it's set to 0, AppVMs will get 0, 1, 2, etc.
    # It is also possible to override the auto assinged CID using the vms.cid option
    vsockBaseCID = lib.mkOption {
      type = lib.types.int;
      default = 0;
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
