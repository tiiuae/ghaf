# Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  config,
  lib,
  pkgs,
  ...
}: let
  inherit (lib) mkOption types optional;

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
    appvmConfiguration = {
      imports = [
        (import ./common/vm-networking.nix {
          inherit config lib vmName;
          inherit (vm) macAddress;
          internalIP = index + 100;
        })
        (import ../../../common/log/logging-client.nix {
          inherit config lib pkgs;
          hostName = vmName;
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
          runWaypipe = pkgs.writeScriptBin "run-waypipe" ''
            #!${pkgs.runtimeShell} -e
            ${pkgs.waypipe}/bin/waypipe --vsock -s ${toString configHost.ghaf.virtualization.microvm.guivm.waypipePort} ${waypipeBorder} server "$@"
          '';
        in {
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
              withName = "appvm-systemd";
              withNss = true;
              withResolved = true;
              withPolkit = true;
              withDebug = configHost.ghaf.profiles.debug.enable;
              withHardenedConfigs = true;
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
            pkgs.tpm2-tools
            pkgs.opensc
          ];

          security.tpm2 = {
            enable = true;
            abrmd.enable = true;
          };

          microvm = {
            optimize.enable = false;
            mem = vm.ramMb;
            vcpu = vm.cores;
            hypervisor = "qemu";
            shares = [
              {
                tag = "waypipe-ssh-public-key";
                source = configHost.ghaf.security.sshKeys.waypipeSshPublicKeyDir;
                mountPoint = configHost.ghaf.security.sshKeys.waypipeSshPublicKeyDir;
              }
              {
                tag = "ro-store";
                source = "/nix/store";
                mountPoint = "/nix/.ro-store";
              }
            ];
            writableStoreOverlay = lib.mkIf config.ghaf.development.debug.tools.enable "/nix/.rw-store";

            qemu = {
              extraArgs =
                [
                  "-M"
                  "accel=kvm:tcg,mem-merge=on,sata=off"
                  "-device"
                  "vhost-vsock-pci,guest-cid=${toString cid}"
                ]
                ++ lib.optionals vm.vtpm.enable [
                  "-chardev"
                  "socket,id=chrtpm,path=/var/lib/swtpm/${vm.name}-sock"
                  "-tpmdev"
                  "emulator,id=tpm0,chardev=chrtpm"
                  "-device"
                  "tpm-tis,tpmdev=tpm0"
                ];

              machine =
                {
                  # Use the same machine type as the host
                  x86_64-linux = "q35";
                  aarch64-linux = "virt";
                }
                .${configHost.nixpkgs.hostPlatform.system};
            };
          };
          fileSystems."${configHost.ghaf.security.sshKeys.waypipeSshPublicKeyDir}".options = ["ro"];

          imports = [../../../common];
        })
      ];
    };
  in {
    autostart = true;
    config = appvmConfiguration // {imports = appvmConfiguration.imports ++ cfg.extraModules ++ vm.extraModules ++ [{environment.systemPackages = vm.packages;}];};
  };

  # Host service dependencies
  after = optional configHost.sound.enable "pulseaudio.service";
  requires = after;
  # Sleep appvms to give gui-vm time to start
  serviceConfig.ExecStartPre = "/bin/sh -c 'sleep 8'";
in {
  options.ghaf.virtualization.microvm.appvm = {
    enable = lib.mkEnableOption "appvm";
    vms = mkOption {
      description = ''
        List of AppVMs to be created
      '';
      type = lib.types.listOf (types.submodule {
        options = {
          name = mkOption {
            description = ''
              Name of the AppVM
            '';
            type = types.str;
          };
          packages = mkOption {
            description = ''
              Packages that are included into the AppVM
            '';
            type = types.listOf types.package;
            default = [];
          };
          macAddress = mkOption {
            description = ''
              AppVM's network interface MAC address
            '';
            type = types.str;
          };
          ramMb = mkOption {
            description = ''
              Amount of RAM for this AppVM
            '';
            type = types.int;
          };
          cores = mkOption {
            description = ''
              Amount of processor cores for this AppVM
            '';
            type = types.int;
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
            type = types.int;
            default = 0;
          };
          borderColor = mkOption {
            description = ''
              Border color of the AppVM window
            '';
            type = types.nullOr types.str;
            default = null;
          };
          vtpm.enable = lib.mkEnableOption "vTPM support in the virtual machine";
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

  config = let
    makeSwtpmService = {vm}: let
      swtpmScript = pkgs.writeShellApplication {
        name = "${vm.name}-swtpm";
        runtimeInputs = with pkgs; [coreutils swtpm];
        text = ''
          mkdir -p /var/lib/swtpm/${vm.name}-state
          swtpm socket --tpmstate dir=/var/lib/swtpm/${vm.name}-state \
            --ctrl type=unixio,path=/var/lib/swtpm/${vm.name}-sock \
            --tpm2 \
            --log level=20
        '';
      };
    in
      lib.mkIf vm.vtpm.enable {
        enable = true;
        description = "swtpm service for ${vm.name}";
        path = [swtpmScript];
        wantedBy = ["microvms.target"];
        serviceConfig = {
          Type = "simple";
          User = "microvm";
          Restart = "always";
          StateDirectory = "swtpm";
          StandardOutput = "journal";
          StandardError = "journal";
          ExecStart = "${swtpmScript}/bin/${vm.name}-swtpm";
        };
      };
  in
    lib.mkIf cfg.enable {
      microvm.vms = let
        vms = lib.imap0 (index: vm: {"${vm.name}-vm" = makeVm {inherit index vm;};}) cfg.vms;
      in
        lib.foldr lib.recursiveUpdate {} vms;

      # Apply host service dependencies, add swtpm
      systemd.services = let
        serviceDependencies =
          map (vm: {
            "microvm@${vm.name}-vm" = {
              inherit after requires serviceConfig;
            };
            "${vm.name}-swtpm" = makeSwtpmService {inherit vm;};
          })
          cfg.vms;
      in
        lib.foldr lib.recursiveUpdate {} serviceDependencies;
    };
}
