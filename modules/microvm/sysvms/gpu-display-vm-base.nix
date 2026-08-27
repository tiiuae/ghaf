# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  defaultMem,
  vmName,
}:
{
  lib,
  inputs,
  globalConfig,
  hostConfig,
  ...
}:
let
  timezoneEnabled = lib.ghaf.features.isEnabledFor globalConfig "timezone" vmName;
in
{
  _file = ./gpu-display-vm-base.nix;

  imports = [
    inputs.preservation.nixosModules.preservation
    inputs.self.nixosModules.givc
    inputs.self.nixosModules.hardware-x86_64-guest-kernel
    inputs.self.nixosModules.vm-modules
    inputs.self.nixosModules.profiles
  ];

  ghaf = {
    profiles.debug.enable = lib.mkDefault (globalConfig.debug.enable or false);

    nix.enable = lib.mkDefault (globalConfig.nix.enable or false);
    development = {
      debug.tools.enable = lib.mkDefault (globalConfig.development.debug.tools.enable or false);
    };

    networking.hosts = hostConfig.networking.hosts or { };
    common = hostConfig.common or { };
    users = {
      profile = hostConfig.users.profile or { };
      admin = (hostConfig.users.admin or { }) // {
        addToDockerGroup = lib.mkDefault (hostConfig.users.admin.addToDockerGroup or false);
      };
      managed = hostConfig.users.managed or { };
    };

    identity.vmHostNameExport.enable = true;
    type = "system-vm";

    systemd = {
      enable = true;
      withName = "${lib.removeSuffix "-vm" vmName}vm-systemd";
      withLocaled = true;
      withNss = true;
      withResolved = true;
      withTimesyncd = true;
      withDebug = globalConfig.debug.enable or false;
      withHardenedConfigs = true;
    };

    givc = {
      enable = globalConfig.givc.enable or false;
      debug = globalConfig.givc.debug or false;
    };

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
        enable = globalConfig.storage.encryption.enable or false;
        name = vmName;
      };
    };

    logging = {
      inherit (globalConfig.logging) enable listener;
      journalClient.enable = globalConfig.logging.enable;
    };

    security = {
      fail2ban.enable = globalConfig.security.ssh.debug.enable or false;
      ssh.debug.enable = lib.mkDefault (globalConfig.security.ssh.debug.enable or false);
      ssh.release = {
        enable = lib.mkDefault (globalConfig.security.ssh.release.enable or false);
        inherit (globalConfig.security.ssh.release)
          authorizedKeys
          trustedUserCAKeys
          authorizedKeysOptions
          ;
        allowedPrincipals = lib.mkIf (
          (globalConfig.security.ssh.release.allowedPrincipals or [ ]) != [ ]
        ) globalConfig.security.ssh.release.allowedPrincipals;
      };
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
    vcpu = lib.mkDefault 4;
    mem = lib.mkDefault defaultMem;
    shares = [
      {
        tag = "ghaf-common";
        source = "/persist/common";
        mountPoint = "/etc/common";
        proto = "virtiofs";
      }
    ]
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
    qemu.machine =
      {
        x86_64-linux = "q35";
        aarch64-linux = "virt";
      }
      .${globalConfig.platform.hostSystem or "aarch64-linux"};
  }
  // lib.optionalAttrs (globalConfig.storage.storeOnDisk.enable or false) (
    let
      level = globalConfig.storage.storeOnDisk.compression.level;
      levelSuffix = lib.optionalString (level != null) ",${toString level}";
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
        lz4hc = [ "-zlz4hc${levelSuffix}" ];
        zstd = [
          "-zzstd${levelSuffix}"
          "-E48bit"
        ];
      }
      .${globalConfig.storage.storeOnDisk.compression.algorithm};
    }
  );
}
