# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# Disp VM Base Module
#
# Base config for the display-passthrough VM (Orin AGX,
# experiment/orin-two-vm-host1x). Like gpuvm-base but without GPU-compute
# (CUDA, gpu-vm-load, /dev/nvgpu): disp-vm owns only display/scanout
# passthrough via ghaf.hardware.definition.dispvm.extraModules.
#
# Usage in profiles:
#   lib.nixosSystem {
#     modules = [ inputs.self.nixosModules.dispvm-base ];
#     specialArgs = { inherit globalConfig hostConfig; };
#   }
#
# Then extend with:
#   base.extendModules { modules = [ ... ]; }
#
{
  lib,
  inputs,
  globalConfig,
  hostConfig,
  ...
}:
let
  vmName = "disp-vm";
  timezoneEnabled = lib.ghaf.features.isEnabledFor globalConfig "timezone" vmName;
in
{
  _file = ./dispvm-base.nix;

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

    # Networking hosts - from hostConfig
    # Required for vm-networking.nix to look up this VM's MAC/IP
    networking.hosts = hostConfig.networking.hosts or { };

    # Common namespace - from hostConfig
    common = hostConfig.common or { };

    # User configuration - from hostConfig
    users = {
      profile = hostConfig.users.profile or { };
      admin = hostConfig.users.admin or { };
      managed = hostConfig.users.managed or { };
    };

    # Enable dynamic hostname export for VMs
    identity.vmHostNameExport.enable = true;

    # System
    type = "system-vm";

    systemd = {
      enable = true;
      withName = "dispvm-systemd";
      withLocaled = true;
      withNss = true;
      withResolved = true;
      withTimesyncd = true;
      withDebug = globalConfig.debug.enable or false;
      withHardenedConfigs = true;
    };

    # GIVC - from globalConfig. ponytail: no dispvm givc role; enable
    # transport only, like gpuvm-base.
    givc = {
      enable = globalConfig.givc.enable or false;
      debug = globalConfig.givc.debug or false;
    };

    # Storage - from globalConfig
    storagevm = {
      enable = true;
      name = vmName;
      encryption.enable = globalConfig.storage.encryption.enable or false;
    };

    virtualization.microvm = {
      swap.enable = true;

      vm-networking = {
        enable = true;
        inherit vmName;
      };

      tpm.emulated = {
        # aarch64: TPM passthrough is x86-only, so emulate when encryption on.
        enable = globalConfig.storage.encryption.enable or false;
        name = vmName;
      };
    };

    # Logging - from globalConfig
    logging = {
      inherit (globalConfig.logging) enable listener;
      journalClient = {
        inherit (globalConfig.logging) enable;
      };
    };

    security = {
      fail2ban.enable = globalConfig.development.ssh.daemon.enable or false;
      audit.enable = lib.mkDefault (globalConfig.security.audit.enable or false);

      spire.agents.downstream = {
        enable = globalConfig.spire.enable or false;
        logLevel = if globalConfig.spire.debug then "DEBUG" else "INFO";
        nodeAttestationMode = if globalConfig.givc.enable then "x509pop" else "join_token";
      };
    };

    services.timezone.enable = lib.mkDefault (
      timezoneEnabled && globalConfig.platform.timeZone == null
    );
  };

  time.timeZone = lib.mkIf (!timezoneEnabled) (lib.mkDefault globalConfig.platform.timeZone);

  system.stateVersion = lib.trivial.release;

  nixpkgs = {
    buildPlatform.system = globalConfig.platform.buildSystem or "x86_64-linux";
    hostPlatform.system = globalConfig.platform.hostSystem or "aarch64-linux";
  };

  microvm = {
    optimize.enable = false;
    # ponytail: vcpu=4 matches tegra234-dispvm.dts cpus node; mem is a
    # display-only default, smaller than GPU VM's 6000.
    vcpu = 4;
    mem = lib.mkDefault 4000;
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
      }
    ];

    writableStoreOverlay = lib.mkIf (
      !(globalConfig.storage.storeOnDisk.enable or false)
    ) "/nix/.rw-store";

    qemu = {
      machine =
        {
          x86_64-linux = "q35";
          aarch64-linux = "virt";
        }
        .${globalConfig.platform.hostSystem or "aarch64-linux"};
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
      storeDiskErofsFlags = [
        "-Eztailpacking"
        "-Efragments"
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
