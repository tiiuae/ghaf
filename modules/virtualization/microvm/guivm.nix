# Copyright 2022-2023 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  config,
  lib,
  pkgs,
  ...
}: let
  configHost = config;
  waypipe-ssh = pkgs.callPackage ../../../user-apps/waypipe-ssh {};
  guivmBaseConfiguration = {
    imports = [
      ({
        lib,
        pkgs,
        ...
      }: {
        ghaf = {
          users.accounts.enable = lib.mkDefault configHost.ghaf.users.accounts.enable;
          profiles.graphics.enable = true;
          profiles.applications.enable = false;
          windows-launcher.enable = false;
          development = {
            # NOTE: SSH port also becomes accessible on the network interface
            #       that has been passed through to NetVM
            ssh.daemon.enable = lib.mkDefault configHost.ghaf.development.ssh.daemon.enable;
            debug.tools.enable = lib.mkDefault configHost.ghaf.development.debug.tools.enable;
          };
        };

        environment = {
          etc = {
            "ssh/waypipe-ssh".source = "${waypipe-ssh}/keys/waypipe-ssh";
          };
          systemPackages = [
            pkgs.waypipe
          ];
        };

        networking.hostName = "guivm";
        system.stateVersion = lib.trivial.release;

        nixpkgs.buildPlatform.system = configHost.nixpkgs.buildPlatform.system;
        nixpkgs.hostPlatform.system = configHost.nixpkgs.hostPlatform.system;

        networking = {
          enableIPv6 = false;
          interfaces.ethint0.useDHCP = false;
          firewall.allowedTCPPorts = [22];
          firewall.allowedUDPPorts = [67];
          useNetworkd = true;
        };

        microvm = {
          mem = 2048;
          hypervisor = "qemu";

          shares = [
            {
              tag = "ro-store";
              source = "/nix/store";
              mountPoint = "/nix/.ro-store";
            }
          ];
          writableStoreOverlay = lib.mkIf config.ghaf.development.debug.tools.enable "/nix/.rw-store";

          interfaces = [
            {
              type = "tap";
              id = "vm-guivm";
              mac = "02:00:00:02:02:02";
            }
          ];

          qemu.extraArgs = [
            "-device"
            "vhost-vsock-pci,guest-cid=${toString cfg.vsockCID}"
          ];
        };

        networking.nat = {
          enable = true;
          internalInterfaces = ["ethint0"];
        };

        # Set internal network's interface name to ethint0
        systemd.network.links."10-ethint0" = {
          matchConfig.PermanentMACAddress = "02:00:00:02:02:02";
          linkConfig.Name = "ethint0";
        };

        systemd.network = {
          enable = true;
          networks."10-ethint0" = {
            matchConfig.MACAddress = "02:00:00:02:02:02";
            addresses = [
              {
                # IP-address for debugging subnet
                addressConfig.Address = "192.168.101.3/24";
              }
            ];
            routes = [
              {routeConfig.Gateway = "192.168.101.1";}
            ];
            linkConfig.RequiredForOnline = "routable";
            linkConfig.ActivationPolicy = "always-up";
          };
        };

        imports = import ../../module-list.nix;

        # Waypipe service runs in the GUIVM and listens for incoming connections from AppVMs
        systemd.user.services.waypipe = {
          enable = true;
          description = "waypipe";
          after = ["weston.service"];
          serviceConfig = {
            Type = "simple";
            Environment = [
              "WAYLAND_DISPLAY=\"wayland-1\""
              "DISPLAY=\":0\""
              "XDG_SESSION_TYPE=wayland"
              "QT_QPA_PLATFORM=\"wayland\"" # Qt Applications
              "GDK_BACKEND=\"wayland\"" # GTK Applications
              "XDG_SESSION_TYPE=\"wayland\"" # Electron Applications
              "SDL_VIDEODRIVER=\"wayland\""
              "CLUTTER_BACKEND=\"wayland\""
            ];
            ExecStart = "${pkgs.waypipe}/bin/waypipe --vsock -s ${toString cfg.waypipePort} client";
            Restart = "always";
            RestartSec = "1";
          };
          wantedBy = ["ghaf-session.target"];
        };
      })
    ];
  };
  cfg = config.ghaf.virtualization.microvm.guivm;
  vsockproxy = pkgs.callPackage ../../../user-apps/vsockproxy {};
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
    microvm.vms."guivm" = {
      autostart = true;
      config =
        guivmBaseConfiguration
        // {
          imports =
            guivmBaseConfiguration.imports
            ++ cfg.extraModules;
        };
      specialArgs = {inherit lib;};
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
