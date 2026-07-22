# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# Peripherals VM Base Module
#
# This module contains the core Peripherals VM configuration and can be composed using extendModules.
# It takes globalConfig and hostConfig via specialArgs for configuration.
#
# Usage in profiles:
#   lib.nixosSystem {
#     modules = [ inputs.self.nixosModules.peripheralsvm-base ];
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
  vmName = "periph-vm";

  timezoneEnabled = lib.ghaf.features.isEnabledFor globalConfig "timezone" vmName;

  # jarekk: clean it
  # globalConfig -> nixosConfigurations.lenovo-x1-carbon-gen11-debug.config.ghaf.global-config.
  usbipCfg =
    # globalConfig.virtualization.microvm.peripheralsvm.usbip or
    {
      enable = true;
      targetVms = [ ];
      port = 3240;
    };
in
{
  _file = ./peripheralsvm-base.nix;

  imports = [
    inputs.preservation.nixosModules.preservation
    inputs.self.nixosModules.givc
    inputs.self.nixosModules.hardware-x86_64-guest-kernel
    inputs.self.nixosModules.vm-modules
    inputs.self.nixosModules.profiles
  ];

  ghaf = {
    # Profiles - from globalConfig
    profiles.debug.enable = globalConfig.debug.enable;

    development = {
      ssh.daemon.enable = lib.mkDefault (globalConfig.development.ssh.daemon.enable or false);
      debug.tools.enable = lib.mkDefault (globalConfig.development.debug.tools.enable or false);
      nix-setup.enable = lib.mkDefault (globalConfig.development.nix-setup.enable or false);
    };

    # System
    type = "system-vm";

    # Enable dynamic hostname export for VMs
    identity.vmHostNameExport.enable = true;

    # Storage - from globalConfig
    storagevm = {
      enable = true;
      name = vmName;
      encryption.enable = globalConfig.storage.encryption.enable or false;
    };

    # Networking
    virtualization.microvm = {
      swap.enable = true;

      vm-networking = {
        enable = true;
        inherit vmName;
      };

    };

    # Logging - from globalConfig
    logging = {
      inherit (globalConfig.logging) enable listener;
      journalClient = {
        inherit (globalConfig.logging) enable;
      };
    };

    # jarekk: TODO: fix it. Probablyit causes ssh disconnections
    # security = {
    #   fail2ban.enable = globalConfig.development.ssh.daemon.enable or false;
    #   spire.agent = {
    #     enable = globalConfig.spire.enable or false;
    #     logLevel = if globalConfig.spire.debug then "DEBUG" else "INFO";
    #     nodeAttestationMode = if globalConfig.givc.enable then "x509pop" else "join_token";
    #   };
    # };

    # Networking hosts - from hostConfig (for vm-networking.nix to look up MAC/IP)
    networking.hosts = hostConfig.networking.hosts or { };
    # Common namespace - from hostConfig (previously from commonModule in modules.nix)
    common = hostConfig.common or { };

    # User configuration - from hostConfig
    users = {
      profile = hostConfig.users.profile or { };
      admin = hostConfig.users.admin or { };
      managed = hostConfig.users.managed or { };
    };

    # GIVC configuration - from globalConfig
    givc = {
      enable = globalConfig.givc.enable or false;
      debug = globalConfig.givc.debug or false;
    };

    # Security - from globalConfig
    security.audit.enable = lib.mkDefault (globalConfig.security.audit.enable or false);
  };

  # USB/IP server for forwarding USB devices to target VMs
  boot = lib.mkIf usbipCfg.enable {
    kernelModules = [
      "usbip_core"
      "usbip_host"
    ];
  };

  environment.systemPackages = lib.mkIf usbipCfg.enable [
    pkgs.linuxPackages.usbip
    # jarekk: remove the packages after testing
    pkgs.usbutils
    pkgs.pciutils
  ];

  systemd.services = lib.mkIf usbipCfg.enable {
    usbipd = {
      description = "USB/IP daemon for forwarding USB devices to target VMs";
      wantedBy = [ "multi-user.target" ];
      after = [ "network.target" ];
      serviceConfig = {
        ExecStart = "${pkgs.linuxPackages.usbip}/bin/usbipd --debug";
        Restart = "on-failure";
        RestartSec = "5s";
        Type = "simple";
      };
    };
  };

  networking.firewall = lib.mkIf usbipCfg.enable {
    allowedTCPPorts = [ usbipCfg.port ];
  };

  time.timeZone = lib.mkIf (!timezoneEnabled) (lib.mkDefault globalConfig.platform.timeZone);

  system.stateVersion = lib.trivial.release;

  nixpkgs = {
    buildPlatform.system = globalConfig.platform.buildSystem or "x86_64-linux";
    hostPlatform.system = globalConfig.platform.hostSystem or "x86_64-linux";
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
    ++ lib.optionals (!(globalConfig.storage.storeOnDisk.enable or false)) [
      {
        tag = "ro-store";
        source = "/nix/store";
        mountPoint = "/nix/.ro-store";
        proto = "virtiofs";
        cache = "always";
      }
    ];

    writableStoreOverlay = lib.mkIf (
      !(globalConfig.storage.storeOnDisk.enable or false)
    ) "/nix/.rw-store";

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
  // lib.optionalAttrs (globalConfig.storage.storeOnDisk.enable or false) (
    let
      compLevelSuffix = lib.optionalString (
        globalConfig.storage.storeOnDisk.compression.level != null
      ) ",${toString globalConfig.storage.storeOnDisk.compression.level}";
    in
    {
      storeOnDisk = true;
      storeDiskType = "erofs";
      # Defaults: -zlz4hc (all kernels), -Eztailpacking (5.16+), -Efragments (6.1+)
      # -zzstd requires Linux 6.15+ due to -E48bit (extended addressing, needed for zstd)
      # Setting storeDiskErofsFlags overrides the entire list; include defaults explicitly if needed.
      storeDiskErofsFlags = [
        "-Eztailpacking"
        "-Efragments"
        # no need to hammer all available cores
        "--workers=$(( (NIX_BUILD_CORES < 1 || NIX_BUILD_CORES > 4) ? 4 : NIX_BUILD_CORES ))"
      ]
      ++ {
        lz4hc = [ "-zlz4hc${compLevelSuffix}" ];
        zstd = [
          "-zzstd${compLevelSuffix}"
          "-E48bit"
        ];
      }
      .${globalConfig.storage.storeOnDisk.compression.algorithm};
    }
  );
}
