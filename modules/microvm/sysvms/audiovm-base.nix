# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# Audio VM Base Module
#
# This module contains the core Audio VM configuration and can be composed using extendModules.
# It takes globalConfig and hostConfig via specialArgs for configuration.
#
# Usage in profiles:
#   lib.nixosSystem {
#     modules = [ inputs.self.nixosModules.audiovm-base ];
#     specialArgs = { inherit globalConfig hostConfig; };
#   }
#
# Then extend with:
#   base.extendModules { modules = [ ... ]; }
#
{
  config,
  lib,
  pkgs,
  inputs,
  globalConfig,
  hostConfig,
  ...
}:
let
  vmName = "audio-vm";
  audioEnabled = lib.ghaf.features.isEnabledFor globalConfig "audio" vmName;
  bluetoothEnabled = lib.ghaf.features.isEnabledFor globalConfig "bluetooth" vmName;
  powerManagerEnabled = lib.ghaf.features.isEnabledFor globalConfig "power-manager" vmName;
  performanceEnabled = lib.ghaf.features.isEnabledFor globalConfig "performance" vmName;
in
{
  _file = ./audiovm-base.nix;

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
      ssh.daemon.enable = lib.mkDefault (globalConfig.development.ssh.daemon.enable or false);
      debug.tools.enable = lib.mkDefault (globalConfig.development.debug.tools.enable or false);
      nix-setup.enable = lib.mkDefault (globalConfig.development.nix-setup.enable or false);
    };

    users.proxyUser = {
      enable = true;
      extraGroups = [
        "audio"
        "pipewire"
      ]
      ++ lib.optional bluetoothEnabled "bluetooth";
    };

    # System
    type = "system-vm";

    systemd = {
      enable = true;
      withName = "audiovm-systemd";
      withLocaled = true;
      withAudio = lib.mkDefault audioEnabled;
      withBluetooth = lib.mkDefault bluetoothEnabled;
      withNss = true;
      withPolkit = true;
      withResolved = true;
      withTimesyncd = true;
      withDebug = globalConfig.debug.enable or false;
      withHardenedConfigs = true;
    };

    givc.audiovm.enable = true;

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
      vm-networking = {
        enable = true;
        inherit vmName;
      };

      tpm.passthrough = {
        # TPM passthrough is only supported on x86_64
        enable =
          (globalConfig.storage.encryption.enable or false)
          && ((globalConfig.platform.hostSystem or "") == "x86_64-linux");
        rootNVIndex = "0x81702000"; # TPM2 NV index for audio-vm LUKS key
      };

      tpm.emulated = {
        # Use emulated TPM for non-x86_64 systems when encryption is enabled
        enable =
          (globalConfig.storage.encryption.enable or false)
          && ((globalConfig.platform.hostSystem or "") != "x86_64-linux");
        name = vmName;
      };
    };

    # Services
    services = {
      audio = {
        enable = lib.mkDefault audioEnabled;
        role = "server";
        server.pipewireForwarding.enable = true;
      };

      firmware.enable = true;

      power-manager = {
        enable = lib.mkDefault powerManagerEnabled;
        vm = {
          enable = true;
          pciSuspendServices =
            lib.optional audioEnabled "pipewire.socket"
            ++ lib.optional audioEnabled "pipewire.service"
            ++ lib.optional bluetoothEnabled "bluetooth.service";
        };
      };

      performance = {
        enable = lib.mkDefault performanceEnabled;
        vm.enable = true;
      };
    };

    # Logging - from globalConfig
    logging = {
      inherit (globalConfig.logging) enable listener;
      client.enable = globalConfig.logging.enable or false;
      server.endpoint = globalConfig.logging.server.endpoint or "";
    };

    security.fail2ban.enable = globalConfig.development.ssh.daemon.enable or false;

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

  environment = {
    systemPackages = [
      pkgs.pulseaudio
      pkgs.pamixer
      pkgs.pipewire
    ]
    ++ lib.optional (config.ghaf.development.debug.tools.enable or false) pkgs.alsa-utils;
  };

  # Allow runtime timezone changes via GIVC set-timezone.
  time.timeZone = null;
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
    mem = lib.mkDefault 384;
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
