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

  sshKeysHelper = pkgs.callPackage ../../../../packages/ssh-keys-helper {
    inherit pkgs;
    config = configHost;
  };

  makeVm = {
    vm,
    index,
  }: let
    vmName = "${vm.name}-vm";
    cid =
      if vm.cid > 0
      then vm.cid
      else cfg.vsockBaseCID + index;
    memsocket = pkgs.callPackage ../../../../packages/memsocket {
      debug = false;
      vms = configHost.ghaf.profiles.applications.ivShMemServer.vmCount;
    };
    memtest = pkgs.callPackage ../../../../packages/memsocket/memtest.nix {};
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
              ${pkgs.waypipe}/bin/waypipe --vsock -s ${toString configHost.ghaf.virtualization.microvm.guivm.waypipePort} ${waypipeBorder} server $@
            '';
        in {
          ghaf = {
            users.accounts.enable = lib.mkDefault configHost.ghaf.users.accounts.enable;

            development = {
              ssh.daemon.enable = lib.mkDefault configHost.ghaf.development.ssh.daemon.enable;
              debug.tools.enable = lib.mkDefault configHost.ghaf.development.debug.tools.enable;
              nix-setup.enable = lib.mkDefault configHost.ghaf.development.nix-setup.enable;
            };
            systemd = {
              enable = true;
              withName = "appvm-systemd";
              withNss = true;
              withResolved = true;
              withPolkit = true;
              withDebug = configHost.ghaf.profiles.debug.enable;
            };
          };

          # SSH is very picky about the file permissions and ownership and will
          # accept neither direct path inside /nix/store or symlink that points
          # there. Therefore we copy the file to /etc/ssh/get-auth-keys (by
          # setting mode), instead of symlinking it.
          environment.etc.${configHost.ghaf.security.sshKeys.getAuthKeysFilePathInEtc} = sshKeysHelper.getAuthKeysSource;
          services.openssh = configHost.ghaf.security.sshKeys.sshAuthorizedKeysCommand;

          system.stateVersion = lib.trivial.release;

          nixpkgs.buildPlatform.system = configHost.nixpkgs.buildPlatform.system;
          nixpkgs.hostPlatform.system = configHost.nixpkgs.hostPlatform.system;

          environment.systemPackages = [
            pkgs.waypipe
            runWaypipe
            memsocket
            memtest
            pkgs.linuxPackages.perf
            pkgs.perf-tools
          ];

          microvm = {
            optimize.enable = false;
            mem = vm.ramMb;
            vcpu = vm.cores;
            kernelParams =
              if configHost.ghaf.profiles.applications.ivShMemServer.enable
              then [
                "kvm_ivshmem.flataddr=${configHost.ghaf.profiles.applications.ivShMemServer.flataddr}"
              ]
              else [];
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
              extraArgs = let
                vectors = toString (2 * configHost.ghaf.profiles.applications.ivShMemServer.vmCount);
                sharedMemory =
                  if configHost.ghaf.profiles.applications.ivShMemServer.enable
                  then [
                    "-device"
                    "ivshmem-doorbell,vectors=${vectors},chardev=ivs_socket,flataddr=${configHost.ghaf.profiles.applications.ivShMemServer.flataddr}"
                    "-chardev"
                    "socket,path=${configHost.ghaf.profiles.applications.ivShMemServer.hostSocketPath},id=ivs_socket"
                  ]
                  else [];
              in
                [
                  "-M"
                  "accel=kvm:tcg,mem-merge=on"
                  "-device"
                  "vhost-vsock-pci,guest-cid=${toString cid}"
                ]
                ++ sharedMemory;

              machine =
                {
                  # Use the same machine type as the host
                  x86_64-linux = "q35";
                  aarch64-linux = "virt";
                }
                .${configHost.nixpkgs.hostPlatform.system};
            };
          };

          boot.kernelPatches =
            if configHost.ghaf.profiles.applications.ivShMemServer.enable
            then [
              {
                name = "Shared memory PCI driver";
                patch = pkgs.fetchpatch {
                  url = "https://raw.githubusercontent.com/tiiuae/shmsockproxy/main/0001-ivshmem-driver.patch";
                  sha256 = "sha256-u/MNrGnSqC4yJenp6ey1/gLNbt2hZDDBCDA6gjQlC7g=";
                };
                extraConfig = ''
                  KVM_IVSHMEM_VM_COUNT ${toString configHost.ghaf.profiles.applications.ivShMemServer.vmCount}
                '';
              }
            ]
            else [];

          services.udev.extraRules =
            if configHost.ghaf.profiles.applications.ivShMemServer.enable
            then ''
              SUBSYSTEM=="misc",KERNEL=="ivshmem",GROUP="kvm",MODE="0666"
            ''
            else "";

          systemd.user.services.memsocket = lib.mkIf configHost.ghaf.profiles.applications.ivShMemServer.enable {
            enable = true;
            description = "memsocket";
            serviceConfig = {
              Type = "simple";
              ExecStart = "${memsocket}/bin/memsocket -s ${configHost.ghaf.profiles.applications.ivShMemServer.serverSocketPath} ${builtins.toString index}";
              Restart = "always";
              RestartSec = "1";
            };
            wantedBy = ["default.target"];
          };

          imports = [../../../common];
        })
      ];
    };
  in {
    autostart = true;
    config = appvmConfiguration // {imports = appvmConfiguration.imports ++ cfg.extraModules ++ vm.extraModules ++ [{environment.systemPackages = vm.packages;}];};
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
