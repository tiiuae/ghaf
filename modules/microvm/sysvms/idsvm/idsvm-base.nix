# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# IDS VM Base Module
#
# This module contains the full IDS VM configuration and can be composed using extendModules.
# It takes globalConfig and hostConfig via specialArgs for configuration.
#
# Usage in profiles:
#   lib.nixosSystem {
#     modules = [ inputs.self.nixosModules.idsvm-base ];
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
  vmName = "ids-vm";
in
{
  _file = ./idsvm-base.nix;

  imports = [
    inputs.preservation.nixosModules.preservation
    inputs.self.nixosModules.vm-modules
    inputs.self.nixosModules.givc
    inputs.self.nixosModules.hardware-x86_64-guest-kernel
    inputs.self.nixosModules.profiles
    ./mitmproxy
  ];

  ghaf = {
    type = "system-vm";

    systemd = {
      enable = true;
      withName = "idsvm-systemd";
      withLocaled = true;
      withNss = true;
      withPolkit = true;
      withResolved = true;
      withTimesyncd = true;
      withDebug = globalConfig.debug.enable or false;
      withHardenedConfigs = true;
    };

    profiles.debug.enable = lib.mkDefault (globalConfig.debug.enable or false);

    givc = {
      enable = globalConfig.givc.enable or false;
      debug = globalConfig.givc.debug or false;
    };

    # MiTM proxy feature - from globalConfig
    virtualization.microvm.idsvm.mitmproxy.enable = globalConfig.idsvm.mitmproxy.enable or false;

    development = {
      # NOTE: SSH port also becomes accessible on the network interface
      #       that has been passed through to NetVM
      ssh.daemon.enable = lib.mkDefault (globalConfig.development.ssh.daemon.enable or false);
      debug.tools.enable = lib.mkDefault (globalConfig.development.debug.tools.enable or false);
      nix-setup.enable = lib.mkDefault (globalConfig.development.nix-setup.enable or false);
    };

    virtualization.microvm.swap.enable = true;

    virtualization.microvm.tpm.passthrough = {
      # At the moment the TPM is only used for storage encryption, so the features are coupled.
      # TPM passthrough is only supported on x86_64.
      enable =
        (globalConfig.storage.encryption.enable or false)
        && ((globalConfig.platform.hostSystem or "") == "x86_64-linux");
      rootNVIndex = "0x81705000"; # TPM2 NV index for ids-vm LUKS key
    };

    virtualization.microvm.tpm.emulated = {
      # Use emulated TPM for non-x86_64 systems when encryption is enabled
      enable =
        (globalConfig.storage.encryption.enable or false)
        && ((globalConfig.platform.hostSystem or "") != "x86_64-linux");
      name = vmName;
    };

    # Logging - from globalConfig
    logging = {
      inherit (globalConfig.logging) enable listener;
      journalClient = {
        inherit (globalConfig.logging) enable;
      };
    };

    # Persistent storage required for journal retention and FSS sealing keys
    storagevm = {
      enable = true;
      name = vmName;
      encryption.enable = globalConfig.storage.encryption.enable or false;
    };

    # Networking - IDS VM is passive (monitoring only, not a gateway)
    virtualization.microvm.vm-networking = {
      enable = true;
      isGateway = false;
      inherit vmName;
    };

    # Networking hosts - from hostConfig (for vm-networking.nix to look up MAC/IP)
    networking.hosts = hostConfig.networking.hosts or { };

    # Common namespace - from hostConfig (previously from commonModule in modules.nix)
    common = hostConfig.common or { };
  };

  system.stateVersion = lib.trivial.release;

  nixpkgs = {
    buildPlatform.system = globalConfig.platform.buildSystem or "x86_64-linux";
    hostPlatform.system = globalConfig.platform.hostSystem or "x86_64-linux";
  };

  ghaf.virtualization.microvm.trafficMirror.receiver.enable =
    globalConfig.idsvm.passiveMonitor.enable or false;

  # IDS-specific packages
  environment.systemPackages = [
    pkgs.snort # TODO: put into separate module
  ]
  ++ (lib.optional (globalConfig.debug.enable or false) pkgs.tcpdump);

  microvm = {
    hypervisor = "qemu";
    optimize.enable = true;
    # Sensible defaults - can be overridden via vmConfig
    vcpu = lib.mkDefault 2;
    mem = lib.mkDefault 512;

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
