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
            extraArgs = [
              "-device"
              "vhost-vsock-pci,guest-cid=${toString cfg.vsockCID}"
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

        imports = [
          ../../../common
          ../../../desktop
        ];

        # Waypipe service runs in the GUIVM and listens for incoming connections from AppVMs
        systemd.user.services.waypipe = {
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

    # Waypipe in GUIVM needs to communicate with AppVMs over VSOCK
    # However, VSOCK does not support direct guest to guest communication
    # The vsockproxy app is used on host as a bridge between AppVMs and GUIVM
    # It listens for incoming connections from AppVMs and forwards data to GUIVM
    systemd.services.vsockproxy = {
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
  };
}
