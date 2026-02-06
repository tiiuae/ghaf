# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# GUI VM Base Module (Canonical Reference)
#
# This is the canonical reference for VM base module patterns.
# All other *-base.nix modules should follow this structure.
#
# VM Base Module Pattern:
# =======================
# 1. Function parameters: lib, pkgs, inputs, globalConfig, hostConfig
#    - config is optional (only if VM needs self-reference)
# 2. Set _file for debugging: _file = ./<name>.nix;
# 3. Standard imports: preservation, givc, kernel, vm-modules, profiles
# 4. Use lib.mkDefault for all overrideable options
# 5. Include: system.stateVersion, time.timeZone, nixpkgs.{build,host}Platform
# 6. VM-specific configuration in microvm = { ... }
#
# Composition via specialArgs:
#   - globalConfig: Host's global configuration (debug, development, storage, etc.)
#   - hostConfig: VM-specific config (networking.thisVm, applications, etc.)
#
# Usage in profiles:
#   lib.nixosSystem {
#     modules = [ inputs.self.nixosModules.guivm-base ];
#     specialArgs = lib.ghaf.vm.mkSpecialArgs { ... };
#   }
#
# Then extend with:
#   base.extendModules { modules = [ ../services ]; }
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
  vmName = "gui-vm";
  inherit (lib) rmDesktopEntries;

  # Options for GUIVM applications (passed via hostConfig)
  guivmApplications = hostConfig.guivm.applications or [ ];

  # A list of applications from all AppVMs (accessed via hostConfig)
  enabledVms = lib.filterAttrs (_: vm: vm.enable) (hostConfig.appvms or { });
  virtualApps = lib.lists.concatMap (
    vm: map (app: app // { vmName = "${vm.name}-vm"; }) vm.applications
  ) (lib.attrsets.mapAttrsToList (name: vm: { inherit name; } // vm) enabledVms);

  # Launchers for all virtualized applications that run in AppVMs
  virtualLaunchers = map (
    app:
    let
      # Generate givcName from app name if not provided (same logic as appvm-base.nix)
      givcName = app.givcName or (lib.strings.toLower (lib.replaceStrings [ " " ] [ "-" ] app.name));
    in
    {
      inherit (app) name;
      inherit (app) description;
      vm = app.vmName;
      # Use givc settings from hostConfig
      execPath = "${pkgs.givc-cli}/bin/givc-cli ${hostConfig.givc.cliArgs or ""} start app --vm ${app.vmName} ${givcName}";
      inherit (app) icon;
    }
  ) virtualApps;

  # Launchers for all desktop, non-virtualized applications that run in the GUIVM
  guivmLaunchers = map (app: {
    inherit (app) name;
    inherit (app) description;
    execPath = app.command;
    inherit (app) icon;
  }) guivmApplications;
in
{
  _file = ./guivm-base.nix;

  imports = [
    inputs.self.nixosModules.profiles
    inputs.self.nixosModules.givc
    inputs.self.nixosModules.hardware-x86_64-guest-kernel
    inputs.preservation.nixosModules.preservation
    inputs.self.nixosModules.vm-modules
  ];

  # Reference services are added by profiles via extendModules
  # See: modules/reference/profiles/mvp-user-trial.nix

  ghaf = {
    # Profiles - from globalConfig
    profiles = {
      debug.enable = lib.mkDefault (globalConfig.debug.enable or false);
      graphics.enable = true;
    };

    # User accounts - from hostConfig
    # Full user configuration including profile, admin, and managed users
    users = {
      profile = hostConfig.users.profile or { };
      admin = hostConfig.users.admin or { };
      managed = hostConfig.users.managed or [ ];
      adUsers = {
        enable = hostConfig.users.profile.ad-users.enable or false;
      };
      homedUser = {
        enable = hostConfig.users.profile.homed-user.enable or false;
        fidoAuth = true;
      };
    };

    # Security - from globalConfig
    security.audit.enable = lib.mkDefault (globalConfig.security.audit.enable or false);

    development = {
      ssh.daemon.enable = lib.mkDefault (globalConfig.development.ssh.daemon.enable or false);
      debug.tools.enable = lib.mkDefault (globalConfig.development.debug.tools.enable or false);
      debug.tools.gui.enable = lib.mkDefault (globalConfig.development.debug.tools.enable or false);
      nix-setup.enable = lib.mkDefault (globalConfig.development.nix-setup.enable or false);
    };

    # Networking hosts - from hostConfig
    # Required for vm-networking.nix to look up this VM's MAC/IP
    networking.hosts = hostConfig.networking.hosts or { };

    # Common namespace - from hostConfig
    # Required for killswitch, etc. to access hardware device info
    common = hostConfig.common or { };

    # Enable dynamic hostname export for VMs
    identity.vmHostNameExport.enable = true;

    # System
    type = "system-vm";
    systemd = {
      enable = true;
      withName = "guivm-systemd";
      withHomed = true;
      withLocaled = true;
      withNss = true;
      withResolved = true;
      withTimesyncd = true;
      withDebug = globalConfig.debug.enable or false;
      withHardenedConfigs = true;
    };
    # GIVC configuration - from globalConfig
    givc = {
      enable = globalConfig.givc.enable or false;
      debug = globalConfig.givc.debug or false;
    };
    givc.guivm.enable = true;

    # Storage - from globalConfig
    storagevm = {
      enable = true;
      name = vmName;
      shared-folders = {
        enable = true;
        isGuiVm = true;
      };
      encryption.enable = globalConfig.storage.encryption.enable or false;
    };

    # Networking
    virtualization.microvm.vm-networking = {
      enable = true;
      inherit vmName;
    };

    virtualization.microvm.tpm.passthrough = {
      # TPM passthrough is only supported on x86_64
      enable =
        (globalConfig.storage.encryption.enable or false)
        && ((globalConfig.platform.hostSystem or "") == "x86_64-linux");
      rootNVIndex = "0x81703000";
    };

    virtualization.microvm.tpm.emulated = {
      # Use emulated TPM for non-x86_64 systems when encryption is enabled
      enable =
        (globalConfig.storage.encryption.enable or false)
        && ((globalConfig.platform.hostSystem or "") != "x86_64-linux");
      name = vmName;
    };

    # Create launchers for regular apps running in the GUIVM and virtualized ones if GIVC is enabled
    graphics = {
      boot = {
        enable = true; # Enable graphical boot on gui-vm
        renderer = "gpu"; # Use GPU for graphical boot in gui-vm
      };
      launchers = guivmLaunchers ++ lib.optionals (globalConfig.givc.enable or false) virtualLaunchers;
      cosmic = {
        securityContext.rules = map (vm: {
          identifier = vm.name;
          color = vm.borderColor;
        }) (lib.attrsets.mapAttrsToList (name: vm: { inherit name; } // vm) enabledVms);
      };
    };

    # Logging - from globalConfig
    logging = {
      inherit (globalConfig.logging) enable listener;
      client.enable = globalConfig.logging.enable or false;
      server.endpoint = globalConfig.logging.server.endpoint or "";
    };

    # Services
    services = {
      # Firmware - always enabled for GUI VM (hardware passthrough needs it)
      firmware.enable = true;

      # Feature services - controlled via globalConfig.features
      # Configure via ghaf.global-config.features.{fprint,yubikey,brightness}
      # Each feature has: enable (global toggle) and targetVms (list of VMs)
      # Use lib.ghaf.features.isEnabledFor to check if feature is enabled for this VM
      fprint.enable = lib.mkDefault (lib.ghaf.features.isEnabledFor globalConfig "fprint" vmName);
      yubikey.enable = lib.mkDefault (lib.ghaf.features.isEnabledFor globalConfig "yubikey" vmName);
      brightness.enable = lib.mkDefault (lib.ghaf.features.isEnabledFor globalConfig "brightness" vmName);

      user-provisioning.enable = true;
      audio = {
        enable = true;
        role = "client";
        client = {
          pipewireControl.enable = true;
        };
      };
      power-manager = {
        vm.enable = true;
        gui.enable = true;
      };
      kill-switch.enable = true;

      performance = {
        enable = globalConfig.services.performance.enable or false;
        gui.enable = true;
      };

      github = {
        enable = true;
        token = "xxxxxxxxxxxxxxxxxxxx"; # Will be updated when the user login
        owner = "tiiuae";
        repo = "ghaf-bugreports";
      };

      timezone.enable = true;

      locale.enable = true;

      disks.enable = true;
    };
    xdgitems.enable = true;

    security.fail2ban.enable = globalConfig.development.ssh.daemon.enable or false;
  };

  services = {
    # We dont enable services.blueman because it adds blueman desktop entry
    dbus.packages = [ pkgs.blueman ];

    orbit = {
      enable = true;
      # CI/dev injects enroll secret via virtiofs to avoid baking secrets into images.
      enrollSecretPath = "/etc/common/ghaf/fleet/enroll";
      fleetUrl = "https://fleetdm.vedenemo.dev";
      hostnameFile = "/etc/common/ghaf/hostname";
      rootDir = "/etc/common/ghaf/orbit";
      enableScripts = true;
      hostIdentifier = "specified";
      osqueryPackage = lib.mkForce pkgs."osquery-with-hostname";
    };
  };

  systemd = {
    packages = [ pkgs.blueman ];
    user.services."fleet-desktop".enable = false;

    services."waypipe-ssh-keygen" =
      let
        uid =
          if hostConfig.users.homedUser.enable or false then
            "${toString (hostConfig.users.homedUser.uid or 1000)}"
          else
            "${toString (hostConfig.users.admin.uid or 1000)}";
        pubDir = hostConfig.security.sshKeys.waypipeSshPublicKeyDir or "/run/waypipe-ssh-public-key";
        keygenScript = pkgs.writeShellScriptBin "waypipe-ssh-keygen" ''
          set -xeuo pipefail
          mkdir -p /run/waypipe-ssh
          mkdir -p ${pubDir}
          echo -en "\n\n\n" | ${pkgs.openssh}/bin/ssh-keygen -t ed25519 -f /run/waypipe-ssh/id_ed25519 -C ""
          chown ${uid}:users /run/waypipe-ssh/*
          cp /run/waypipe-ssh/id_ed25519.pub ${pubDir}/id_ed25519.pub
          chown -R ${uid}:users ${pubDir}
        '';
      in
      {
        enable = true;
        description = "Generate SSH keys for Waypipe";
        path = [ keygenScript ];
        wantedBy = [ "multi-user.target" ];
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
          StandardOutput = "journal";
          StandardError = "journal";
          ExecStart = "${keygenScript}/bin/waypipe-ssh-keygen";
        };
      };
  };

  environment = {
    systemPackages =
      (rmDesktopEntries [
        pkgs.waypipe
        pkgs.gnome-calculator
        pkgs.sticky-notes
      ])
      ++ [ pkgs.ctrl-panel ]
      # For GIVC debugging/testing
      ++ lib.optional (globalConfig.debug.enable or false) pkgs.givc-cli
      # Packages for checking hardware acceleration
      ++ lib.optionals (globalConfig.debug.enable or false) [
        pkgs.mesa-demos
        pkgs.libva-utils
        pkgs.glib
      ]
      ++ [ pkgs.vhotplug ];
    sessionVariables = lib.optionalAttrs (globalConfig.debug.enable or false) (
      {
        GIVC_NAME = "admin-vm";
        GIVC_ADDR = hostConfig.networking.hosts."admin-vm".ipv4 or "192.168.101.10";
        GIVC_PORT = "9001";
      }
      // lib.optionalAttrs (hostConfig.givc.enableTls or false) {
        GIVC_CA_CERT = "/run/givc/ca-cert.pem";
        GIVC_HOST_CERT = "/run/givc/cert.pem";
        GIVC_HOST_KEY = "/run/givc/key.pem";
      }
    );
  };

  time.timeZone = globalConfig.platform.timeZone or "UTC";
  system.stateVersion = lib.trivial.release;

  nixpkgs = {
    buildPlatform.system = globalConfig.platform.buildSystem or "x86_64-linux";
    hostPlatform.system = globalConfig.platform.hostSystem or "x86_64-linux";
  };

  microvm = {
    optimize.enable = false;
    # Sensible defaults - can be overridden via vmConfig
    vcpu = lib.mkDefault 6;
    mem = lib.mkDefault 12288;
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
      extraArgs = [
        "-device"
        "qemu-xhci"
        "-device"
        "vhost-vsock-pci,guest-cid=${toString (hostConfig.networking.thisVm.cid or 5)}"
      ];

      machine =
        {
          # Use the same machine type as the host
          x86_64-linux = "q35";
          aarch64-linux = "virt";
        }
        .${globalConfig.platform.hostSystem or "x86_64-linux"};
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
