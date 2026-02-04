# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# Net VM Base Module
#
# This module contains the core Net VM configuration and can be composed using extendModules.
# It takes globalConfig and hostConfig via specialArgs for configuration.
#
# Usage in profiles:
#   lib.nixosSystem {
#     modules = [ inputs.self.nixosModules.netvm-base ];
#     specialArgs = { inherit globalConfig hostConfig; };
#   }
#
# Then extend with:
#   base.extendModules { modules = [ ... ]; }
#
{
  lib,
  pkgs,
  inputs,
  globalConfig,
  hostConfig,
  ...
}:
let
  vmName = "net-vm";
in
{
  _file = ./netvm-base.nix;

  imports = [
    inputs.preservation.nixosModules.preservation
    inputs.self.nixosModules.givc
    inputs.self.nixosModules.hardware-x86_64-guest-kernel
    inputs.self.nixosModules.vm-modules
    inputs.self.nixosModules.profiles
  ];

  ghaf = {
    # Profiles - from globalConfig
    profiles.debug.enable = lib.mkDefault (globalConfig.debug.enable or false);

    development = {
      # NOTE: SSH port also becomes accessible on the network interface
      #       that has been passed through to NetVM
      ssh.daemon.enable = lib.mkDefault (globalConfig.development.ssh.daemon.enable or false);
      debug.tools.enable = lib.mkDefault (globalConfig.development.debug.tools.enable or false);
      debug.tools.net.enable = lib.mkDefault (globalConfig.development.debug.tools.enable or false);
      nix-setup.enable = lib.mkDefault (globalConfig.development.nix-setup.enable or false);
    };

    users = {
      proxyUser = {
        enable = true;
        extraGroups = [
          "networkmanager"
        ];
      };
      # User configuration - from hostConfig
      profile = hostConfig.users.profile or { };
      admin = hostConfig.users.admin or { };
      managed = hostConfig.users.managed or { };
    };

    # Enable dynamic hostname export and setter for NetVM
    identity.vmHostNameExport.enable = true;
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
      withDebug = globalConfig.debug.enable or false;
      withHardenedConfigs = true;
    };
    givc.netvm.enable = true;

    # Storage - from globalConfig
    storagevm = {
      enable = true;
      name = vmName;
      encryption.enable = globalConfig.storage.encryption.enable or false;
    };

    # Networking
    virtualization.microvm.vm-networking = {
      enable = true;
      isGateway = true;
      inherit vmName;
    };

    virtualization.microvm.tpm.passthrough = {
      # At the moment the TPM is only used for storage encryption, so the features are coupled.
      enable = globalConfig.storage.encryption.enable or false;
      rootNVIndex = "0x81704000";
    };

    # Services
    services = {
      # WiFi service - conditional on hostConfig flag
      wifi.enable = lib.mkDefault (hostConfig.netvm.wifi or false);

      # Firmware service
      firmware.enable = true;

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

    # Logging - from globalConfig (includes listener address)
    logging = {
      client.enable = globalConfig.logging.enable or false;
      listener.address = globalConfig.logging.listener.address or "";
      server.endpoint = globalConfig.logging.server.endpoint or "";
    };

    security = {
      fail2ban.enable = globalConfig.development.ssh.daemon.enable or false;
      ssh-tarpit = {
        enable = globalConfig.development.ssh.daemon.enable or false;
        listenAddress = hostConfig.networking.thisVm.ipv4 or "192.168.100.1";
      };
      # Audit - from globalConfig
      audit.enable = lib.mkDefault (globalConfig.security.audit.enable or false);
    };

    # Common namespace - from hostConfig
    common = hostConfig.common or { };

    # Note: reference.services is NOT set here - it should come via extraModules
    # from hardware.definition.netvm.extraModules if needed
  };

  time.timeZone = globalConfig.platform.timeZone or "UTC";
  system.stateVersion = lib.trivial.release;

  nixpkgs = {
    buildPlatform.system = globalConfig.platform.buildSystem or "x86_64-linux";
    hostPlatform.system = globalConfig.platform.hostSystem or "x86_64-linux";
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
    # Optimize is disabled because when it is enabled, qemu is built without libusb
    optimize.enable = false;
    # Sensible defaults - can be overridden via vmConfig
    vcpu = lib.mkDefault 2;
    mem = lib.mkDefault 512;
    hypervisor = "qemu";

    shares = [
      {
        tag = "ghaf-common";
        source = "/persist/common";
        mountPoint = "/etc/common";
        proto = "virtiofs";
      }
    ]
    # Shared store (when not using storeOnDisk)
    ++ lib.optionals (!(globalConfig.storage.storeOnDisk or false)) [
      {
        tag = "ro-store";
        source = "/nix/store";
        mountPoint = "/nix/.ro-store";
        proto = "virtiofs";
      }
    ];

    writableStoreOverlay = lib.mkIf (!(globalConfig.storage.storeOnDisk or false)) "/nix/.rw-store";

    qemu = {
      machine =
        {
          # Use the same machine type as the host
          x86_64-linux = "q35";
          aarch64-linux = "virt";
        }
        .${globalConfig.platform.hostSystem or "x86_64-linux"};
      extraArgs = [
        "-device"
        "qemu-xhci"
      ];
    };
  }
  // lib.optionalAttrs (globalConfig.storage.storeOnDisk or false) {
    storeOnDisk = true;
    storeDiskType = "erofs";
    storeDiskErofsFlags = [
      "-zlz4hc"
      "-Eztailpacking"
    ];
  };
}
