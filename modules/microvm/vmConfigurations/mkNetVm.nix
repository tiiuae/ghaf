# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# Net VM Builder - Creates a standalone, extensible network VM configuration
#
# This function creates a base net VM configuration using lib.nixosSystem.
# The result can be extended via .extendModules for composition.
#
# Note: `inputs` is passed via specialArgs to lib.nixosSystem, so all modules
# (including base.nix) receive it directly - no currying needed.
#
{ inputs, lib }:
{
  # Target system architecture
  system,
  # Shared configuration module (debug/release settings, timezone, etc.)
  systemConfigModule ? { },
  # Additional modules to include
  extraModules ? [ ],
}:
let
  vmName = "net-vm";

  # Net VM specific configuration module (Layer 2: VM role)
  netVmModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    {
      networking.hostName = lib.mkDefault vmName;

      ghaf = {
        users = {
          proxyUser = {
            enable = true;
            extraGroups = [
              "networkmanager"
            ];
          };
        };

        # Enable hostname setter for NetVM (export already in base)
        identity.vmHostNameSetter.enable = true;

        # System
        type = "system-vm";
        systemd = {
          enable = true;
          withName = "netvm-systemd";
          withLocaled = true;
          withPolkit = true;
          withResolved = true;
          withTimesyncd = true;
          withDebug = config.ghaf.profiles.debug.enable;
          withHardenedConfigs = true;
        };
        givc.netvm.enable = true;

        # Storage - base config, encryption enabled via extendModules
        storagevm = {
          enable = true;
          name = vmName;
        };

        # Networking
        virtualization.microvm.vm-networking = {
          enable = true;
          isGateway = true;
          inherit vmName;
        };

        # Services
        services = {
          power-manager.vm = {
            enable = pkgs.stdenv.hostPlatform.isx86;
            pciSuspendServices = [
              "NetworkManager.service"
              "wpa_supplicant.service"
            ];
          };

          performance = {
            net.enable = true;
          };
        };

        # Logging - enabled based on profile
        logging.client.enable = config.ghaf.logging.enable or false;

        # Security
        security.fail2ban.enable = config.ghaf.development.ssh.daemon.enable or false;
      };

      ghaf.firewall =
        let
          dnsPort = 53;
        in
        {
          allowedTCPPorts = [ dnsPort ];
          allowedUDPPorts = [ dnsPort ];
        };

      microvm = {
        shares = [
          {
            tag = "ghaf-common";
            source = "/persist/common";
            mountPoint = "/etc/common";
            proto = "virtiofs";
          }
        ];

        qemu = {
          extraArgs = [
            "-device"
            "qemu-xhci"
          ];
        };
      };
    };
in
lib.nixosSystem {
  inherit system;
  specialArgs = {
    inherit lib inputs;
  };
  modules = [
    # Core microvm module
    inputs.microvm.nixosModules.microvm
    # Guest kernel for x86_64
    inputs.self.nixosModules.hardware-x86_64-guest-kernel
    # Layer 1: Base VM configuration (common defaults) - gets inputs via specialArgs
    ./base.nix
    # nixpkgs configuration (must match host settings)
    {
      nixpkgs = {
        hostPlatform.system = system;
        config = {
          allowUnfree = true;
          permittedInsecurePackages = [
            "jitsi-meet-1.0.8043"
            "qtwebengine-5.15.19"
          ];
        };
        overlays = [ inputs.self.overlays.default ];
      };
    }
    # Layer 3: Shared system configuration (debug/release, timezone, etc.)
    systemConfigModule
    # Layer 2: Net-specific configuration (VM role)
    netVmModule
  ]
  ++ extraModules;
}
