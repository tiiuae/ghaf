# Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  config,
  lib,
  pkgs,
  ...
}: let
  vmName = "gui-vm";
  macAddress = "02:00:00:02:02:02";
  inherit (import ../../../../lib/launcher.nix {inherit pkgs lib;}) rmDesktopEntries;
  guivmBaseConfiguration = {
    imports = [
      (import ./common/vm-networking.nix {
        inherit config lib vmName macAddress;
        internalIP = 3;
      })
      (import ../../../common/log/logging-client.nix {
        inherit config lib pkgs;
        hostName = vmName;
      })
      ({
        lib,
        pkgs,
        ...
      }: {
        ghaf = {
          users.accounts.enable = lib.mkDefault config.ghaf.users.accounts.enable;
          profiles = {
            debug.enable = lib.mkDefault config.ghaf.profiles.debug.enable;
            applications.enable = false;
            graphics.enable = true;
          };
          # To enable screen locking set to true
          graphics.labwc.autolock.enable = false;
          development = {
            ssh.daemon.enable = lib.mkDefault config.ghaf.development.ssh.daemon.enable;
            debug.tools.enable = lib.mkDefault config.ghaf.development.debug.tools.enable;
            nix-setup.enable = lib.mkDefault config.ghaf.development.nix-setup.enable;
          };
          systemd = {
            enable = true;
            withName = "guivm-systemd";
            withNss = true;
            withResolved = true;
            withTimesyncd = true;
            withDebug = config.ghaf.profiles.debug.enable;
            withHardenedConfigs = true;
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
          systemPackages =
            (rmDesktopEntries [
              pkgs.waypipe
              pkgs.networkmanagerapplet
            ])
            ++ [
              pkgs.nm-launcher
              pkgs.pamixer
            ]
            ++ (lib.optional (config.ghaf.profiles.debug.enable && config.ghaf.virtualization.microvm.idsvm.mitmproxy.enable) pkgs.mitmweb-ui);
        };

        time.timeZone = config.time.timeZone;
        system.stateVersion = lib.trivial.release;

        nixpkgs = {
          buildPlatform.system = config.nixpkgs.buildPlatform.system;
          hostPlatform.system = config.nixpkgs.hostPlatform.system;
        };

        # Suspend inside Qemu causes segfault
        # See: https://gitlab.com/qemu-project/qemu/-/issues/2321
        services.logind.lidSwitch = "ignore";

        microvm = {
          optimize.enable = false;
          vcpu = 2;
          mem = 2048;
          hypervisor = "qemu";
          shares = [
            {
              tag = "rw-waypipe-ssh-public-key";
              source = config.ghaf.security.sshKeys.waypipeSshPublicKeyDir;
              mountPoint = config.ghaf.security.sshKeys.waypipeSshPublicKeyDir;
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
              .${config.nixpkgs.hostPlatform.system};
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
          after = ["labwc.service"];
          serviceConfig = {
            Type = "simple";
            ExecStart = "${pkgs.waypipe}/bin/waypipe --vsock -s ${toString cfg.waypipePort} client";
            Restart = "always";
            RestartSec = "1";
          };
          startLimitIntervalSec = 0;
          wantedBy = ["ghaf-session.target"];
        };
      })
    ];
  };
  cfg = config.ghaf.virtualization.microvm.guivm;
  vsockproxy = pkgs.callPackage ../../../../packages/vsockproxy {};

  # Importing kernel builder function and building guest_graphics_hardened_kernel
  buildKernel = import ../../../../packages/kernel {inherit config pkgs lib;};
  config_baseline = ../../../hardware/x86_64-generic/kernel/configs/ghaf_host_hardened_baseline-x86;
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
        mkdir -pv ${config.ghaf.security.sshKeys.waypipeSshPublicKeyDir}
        chown -v microvm ${config.ghaf.security.sshKeys.waypipeSshPublicKeyDir}
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
      serviceConfig = {
        Type = "simple";
        Restart = "always";
        RestartSec = "1";
        ExecStart = "${vsockproxy}/bin/vsockproxy ${toString cfg.waypipePort} ${toString cfg.vsockCID} ${toString cfg.waypipePort}";
      };
      wantedBy = ["multi-user.target"];
    };
  };
}
