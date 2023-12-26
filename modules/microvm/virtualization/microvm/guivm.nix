# Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  config,
  lib,
  pkgs,
  ...
}: let
  configHost = config;
  vmName = "gui-vm";
  macAddress = "02:00:00:02:02:02";
  memsocket = pkgs.callPackage ../../../../packages/memsocket {
    debug = false;
    vms = config.ghaf.profiles.applications.ivShMemServer.vmCount;
  };
  guivmBaseConfiguration = {
    imports = [
      (import ./common/vm-networking.nix {inherit vmName macAddress;})
      ({
        lib,
        pkgs,
        ...
      }: {
        ghaf = {
          users.accounts.enable = lib.mkDefault configHost.ghaf.users.accounts.enable;
          profiles.debug.enable = lib.mkDefault configHost.ghaf.profiles.debug.enable;
          profiles.graphics.enable = true;
          # To enable screen locking set graphics.labwc.lock to true
          graphics.labwc.lock.enable = false;
          profiles.applications.enable = false;
          windows-launcher.enable = false;
          development = {
            ssh.daemon.enable = lib.mkDefault configHost.ghaf.development.ssh.daemon.enable;
            debug.tools.enable = lib.mkDefault configHost.ghaf.development.debug.tools.enable;
            nix-setup.enable = lib.mkDefault configHost.ghaf.development.nix-setup.enable;
          };
          systemd = {
            enable = true;
            withName = "guivm-systemd";
            withNss = true;
            withResolved = true;
            withTimesyncd = true;
            withDebug = configHost.ghaf.profiles.debug.enable;
          };
        };

        systemd.services."waypipe-ssh-keygen" = let
          keygenScript = pkgs.writeShellScriptBin "waypipe-ssh-keygen" ''
            set -xeuo pipefail
            mkdir -p /run/waypipe-ssh
            echo -en "\n\n\n" | ${pkgs.openssh}/bin/ssh-keygen -t ed25519 -f /run/waypipe-ssh/id_ed25519 -C ""
            chown ghaf:ghaf /run/waypipe-ssh/*
            cp /run/waypipe-ssh/id_ed25519.pub /run/waypipe-ssh-public-key/id_ed25519.pub
          '';
        in {
          enable = true;
          description = "Generate SSH keys for Waypipe";
          path = [keygenScript];
          wantedBy = ["multi-user.target"];
          serviceConfig = {
            Type = "oneshot";
            RemainAfterExit = true;
            StandardOutput = "journal";
            StandardError = "journal";
            ExecStart = "${keygenScript}/bin/waypipe-ssh-keygen";
          };
        };

        environment = {
          systemPackages = [
            pkgs.waypipe
            pkgs.networkmanagerapplet
            pkgs.nm-launcher
            memsocket
          ];
        };

        system.stateVersion = lib.trivial.release;

        nixpkgs.buildPlatform.system = configHost.nixpkgs.buildPlatform.system;
        nixpkgs.hostPlatform.system = configHost.nixpkgs.hostPlatform.system;

        microvm = {
          optimize.enable = false;
          vcpu = 2;
          mem = 2048;
          hypervisor = "qemu";
          kernelParams =
            if configHost.ghaf.profiles.applications.ivShMemServer.enable
            then [
              "kvm_ivshmem.flataddr=${configHost.ghaf.profiles.applications.ivShMemServer.flataddr}"
            ]
            else [];

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

          qemu = {
            extraArgs = let
              vectors = toString (2 * config.ghaf.profiles.applications.ivShMemServer.vmCount);
              sharedMemory =
                if configHost.ghaf.profiles.applications.ivShMemServer.enable
                then [
                  "-device"
                  "ivshmem-doorbell,vectors=${vectors},chardev=ivs_socket,flataddr=${config.ghaf.profiles.applications.ivShMemServer.flataddr}"
                  "-chardev"
                  "socket,path=${config.ghaf.profiles.applications.ivShMemServer.hostSocketPath},id=ivs_socket"
                ]
                else [];
            in
              [
                "-device"
                "vhost-vsock-pci,guest-cid=${toString cfg.vsockCID}"
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

        imports = [
          ../../../common
          ../../../desktop
        ];

        services.udev.extraRules = ''
          SUBSYSTEM=="misc",KERNEL=="ivshmem",GROUP="kvm",MODE="0666"
        '';

        # Waypipe service runs in the GUIVM and listens for incoming connections from AppVMs
        systemd.user.services = {
          waypipe = {
            enable = true;
            description = "waypipe";
            after = ["weston.service" "labwc.service"];
            serviceConfig = {
              Type = "simple";
              ExecStart = "${pkgs.waypipe}/bin/waypipe --vsock -s ${toString cfg.waypipePort} client";
              Restart = "always";
              RestartSec = "1";
            };
            startLimitIntervalSec = 0;
            wantedBy = ["ghaf-session.target"];
          };

          # Waypipe in GUIVM needs to communicate with AppVMs using socket forwading
          # application. It uses shared memory between virtual machines to forward
          # data between sockets.
          #
          memsocket = lib.mkIf config.ghaf.profiles.applications.ivShMemServer.enable {
            enable = true;
            description = "memsocket";
            after = ["weston.service"];
            serviceConfig = {
              Type = "simple";
              ExecStart = "${memsocket}/bin/memsocket -c ${config.ghaf.profiles.applications.ivShMemServer.clientSocketPath}";
              Restart = "always";
              RestartSec = "1";
            };
            wantedBy = ["ghaf-session.target"];
          };
        };
        # Fixed IP-address for debugging subnet
        systemd.network.networks."10-ethint0".addresses = [
          {
            addressConfig.Address = "192.168.101.3/24";
          }
        ];
      })
    ];
  };
  cfg = config.ghaf.virtualization.microvm.guivm;
  vsockproxy = pkgs.callPackage ../../../../packages/vsockproxy {};

  # Importing kernel builder function and building guest_graphics_hardened_kernel
  buildKernel = import ../../../packages/kernel {inherit config pkgs lib;};
  config_baseline = ../../hardware/x86_64-generic/kernel/configs/ghaf_host_hardened_baseline-x86;
  guest_graphics_hardened_kernel = buildKernel {inherit config_baseline;};
in {
  options.ghaf.virtualization.microvm.guivm = {
    enable = lib.mkEnableOption "GUIVM";

    extraModules = lib.mkOption {
      description = ''
        List of additional modules to be imported and evaluated as part of
        GUIVM's NixOS configuration.
      '';
      default = [];
    };

    # GUIVM uses a VSOCK which requires a CID
    # There are several special addresses:
    # VMADDR_CID_HYPERVISOR (0) is reserved for services built into the hypervisor
    # VMADDR_CID_LOCAL (1) is the well-known address for local communication (loopback)
    # VMADDR_CID_HOST (2) is the well-known address of the host
    # CID 3 is the lowest available number for guest virtual machines
    vsockCID = lib.mkOption {
      type = lib.types.int;
      default = 3;
      description = ''
        Context Identifier (CID) of the GUIVM VSOCK
      '';
    };

    waypipePort = lib.mkOption {
      type = lib.types.int;
      default = 1100;
      description = ''
        Waypipe port number to listen for incoming connections from AppVMs
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    microvm.vms."${vmName}" = {
      autostart = true;
      config =
        guivmBaseConfiguration
        // {
          boot.kernelPackages =
            lib.mkIf config.ghaf.guest.kernel.hardening.graphics.enable
            (pkgs.linuxPackagesFor guest_graphics_hardened_kernel);

          imports =
            guivmBaseConfiguration.imports
            ++ cfg.extraModules;
        }
        // {
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
                  KVM_IVSHMEM_VM_COUNT ${toString config.ghaf.profiles.applications.ivShMemServer.vmCount}
                '';
              }
            ]
            else [];
        };
    };

    # This directory needs to be created before any of the microvms start.
    systemd.services."create-waypipe-ssh-public-key-directory" = let
      script = pkgs.writeShellScriptBin "create-waypipe-ssh-public-key-directory" ''
        mkdir -pv /run/waypipe-ssh-public-key
        chown -v microvm /run/waypipe-ssh-public-key
      '';
    in {
      enable = true;
      description = "Create shared directory on host";
      path = [];
      wantedBy = ["microvms.target"];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        StandardOutput = "journal";
        StandardError = "journal";
        ExecStart = "${script}/bin/create-waypipe-ssh-public-key-directory";
      };
    };

    systemd.services = {
      # Waypipe in GUIVM needs to communicate with AppVMs over VSOCK
      # However, VSOCK does not support direct guest to guest communication
      # The vsockproxy app is used on host as a bridge between AppVMs and GUIVM
      # It listens for incoming connections from AppVMs and forwards data to GUIVM
      vsockproxy = {
        enable = true;
        description = "vsockproxy";
        unitConfig = {
          Type = "simple";
        };
        serviceConfig = {
          ExecStart = "${vsockproxy}/bin/vsockproxy ${toString cfg.waypipePort} ${toString cfg.vsockCID} ${toString cfg.waypipePort}";
        };
        wantedBy = ["multi-user.target"];
      };

      ivshmemsrv = let
        socketPath = config.ghaf.profiles.applications.ivShMemServer.hostSocketPath;
        pidFilePath = "/tmp/ivshmem-server.pid";
        ivShMemSrv = let
          vectors = toString (2 * config.ghaf.profiles.applications.ivShMemServer.vmCount);
        in
          pkgs.writeShellScriptBin "ivshmemsrv" ''
            chown microvm /dev/hugepages
            chgrp kvm /dev/hugepages
            if [ -S ${socketPath} ]; then
              echo Erasing ${socketPath} ${pidFilePath}
              rm -f ${socketPath}
            fi
            ${pkgs.sudo}/sbin/sudo -u microvm -g kvm ${pkgs.qemu_kvm}/bin/ivshmem-server -p ${pidFilePath} -n ${vectors} -m /dev/hugepages/ -l ${(toString config.ghaf.profiles.applications.ivShMemServer.memSize) + "M"}
            sleep 2
          '';
      in
        lib.mkIf configHost.ghaf.profiles.applications.ivShMemServer.enable {
          enable = true;
          description = "Start qemu ivshmem memory server";
          path = [ivShMemSrv];
          wantedBy = ["multi-user.target"];
          serviceConfig = {
            Type = "oneshot";
            RemainAfterExit = true;
            StandardOutput = "journal";
            StandardError = "journal";
            ExecStart = "${ivShMemSrv}/bin/ivshmemsrv";
          };
        };
    };
  };
}
