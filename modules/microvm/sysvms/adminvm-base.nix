# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# Admin VM Base Module
#
# This module contains the full Admin VM configuration and can be composed using extendModules.
# It takes globalConfig and hostConfig via specialArgs for configuration.
#
# Usage in profiles:
#   lib.nixosSystem {
#     modules = [ inputs.self.nixosModules.adminvm-base ];
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
  vmName = "admin-vm";
in
{
  _file = ./adminvm-base.nix;

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
      #       that has been passed through to VM
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

    # System
    type = "admin-vm";

    systemd = {
      enable = true;
      withName = "adminvm-systemd";
      withLocaled = true;
      withNss = true;
      withResolved = true;
      withPolkit = true;
      withTimesyncd = true;
      withDebug = globalConfig.debug.enable or false;
      withHardenedConfigs = true;
    };

    givc.adminvm.enable = true;

    # Enable dynamic hostname export for VMs
    identity.vmHostNameExport.enable = true;

    # Storage - from globalConfig
    storagevm = {
      enable = true;
      name = vmName;
      files = [
        "/etc/locale-givc.conf"
        "/etc/timezone.conf"
      ];
      directories = lib.mkIf (globalConfig.storage.encryption.enable or false) (
        [
          "/var/lib/swtpm"
        ]
        ++ lib.optionals (globalConfig.spiffe.enable or false) [
          "/var/lib/spire"
        ]
      );
      encryption.enable = globalConfig.storage.encryption.enable or false;
    };

    # Networking
    virtualization.microvm = {
      swap.enable = true;

      vm-networking = {
        enable = true;
        inherit vmName;
      };

      tpm.passthrough = {
        # TPM passthrough supported on x86_64 and aarch64
        enable =
          (globalConfig.storage.encryption.enable or false)
          && ((globalConfig.platform.hostSystem or "") != "riscv64-linux");
        rootNVIndex = "0x81701000"; # TPM2 NV index for admin-vm LUKS key
      };

      tpm.emulated = {
        # Use emulated TPM for platforms without hardware TPM support
        enable =
          (globalConfig.storage.encryption.enable or false)
          && ((globalConfig.platform.hostSystem or "") == "riscv64-linux");
        name = vmName;
      };
    };

    # Logging - from globalConfig
    logging = {
      inherit (globalConfig.logging) enable listener;

      server = {
        inherit (globalConfig.logging) enable;
        endpoint = globalConfig.logging.server.endpoint or "";

        tls = {
          remoteCAFile = null;
          certFile = "/etc/givc/cert.pem";
          keyFile = "/etc/givc/key.pem";
          serverName = "loki.ghaflogs.vedenemo.dev";
          minVersion = "TLS12";

          terminator = {
            backendPort = 3101; # alloy server listens here
            verifyClients = true;
          };
        };
      };

      recovery.enable = true;
    };

    # GIVC configuration - from globalConfig
    givc = {
      inherit (globalConfig.givc) enable;
      inherit (globalConfig.givc) debug;
    };

    # Security
    security = {
      fail2ban.enable = globalConfig.development.ssh.daemon.enable or false;
      audit.enable = lib.mkDefault (globalConfig.security.audit.enable or false);

      # SPIFFE/SPIRE — admin-vm is the SPIRE server
      spiffe = lib.mkIf (globalConfig.spiffe.enable or false) {
        enable = true;
        trustDomain = globalConfig.spiffe.trustDomain or "ghaf.internal";

        server = {
          enable = true;
          bindPort = globalConfig.spiffe.serverPort or 8081;
          # Collect VM names for join token generation:
          # all system VMs + app VMs + ghaf-host
          spireAgentVMs =
            let
              sysvmNames = lib.mapAttrsToList (_: vm: vm.vmName) (hostConfig.sysvms or { });
              appvmNames = lib.mapAttrsToList (name: _: "${name}-vm") (hostConfig.appvms or { });
            in
            sysvmNames ++ appvmNames ++ [ "ghaf-host" ];
          generateJoinTokens = true;
          publishBundle = true;
          createWorkloadEntries = true;
          workloadEntries = [
            {
              name = "workload";
              selectors = [ "unix:user:ghaf" ];
            }
          ];
          tpmAttestation = lib.mkIf (globalConfig.spiffe.tpmAttestation.enable or false) {
            enable = true;
            devidCaPath = "/etc/common/spire/ca/ca.pem";
            endorsementCaBundle = globalConfig.spiffe.tpmAttestation.endorsementCaBundle or "";
          };
        };

        # admin-vm also runs a SPIRE agent
        agent = {
          enable = true;
          serverAddress = "127.0.0.1";
          serverPort = globalConfig.spiffe.serverPort or 8081;
          joinTokenFile = "/etc/common/spire/tokens/${vmName}.token";
        };

        # DevID CA (signs certs for system VMs with TPM)
        devidCa.enable = globalConfig.spiffe.tpmAttestation.enable or false;
      };
    };
  };

  system.stateVersion = lib.trivial.release;
  # Allow runtime timezone changes via GIVC set-timezone.
  time.timeZone = null;

  nixpkgs = {
    buildPlatform.system = globalConfig.platform.buildSystem or "x86_64-linux";
    hostPlatform.system = globalConfig.platform.hostSystem or "x86_64-linux";
  };

  microvm = {
    optimize.enable = false;
    # Sensible defaults - can be overridden via vmConfig
    vcpu = lib.mkDefault 2;
    mem = lib.mkDefault 512;
    #TODO: Add back support cloud-hypervisor
    #the system fails to switch root to the stage2 with cloud-hypervisor
    hypervisor = "qemu";
    qemu = {
      extraArgs = [
        "-device"
        "vhost-vsock-pci,guest-cid=${toString (hostConfig.networking.thisVm.cid or 10)}"
      ];
    };

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
