# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# App VM Base Module
#
# This module contains the core App VM configuration and can be composed using extendModules.
# It takes globalConfig and hostConfig via specialArgs for configuration.
#
# Unlike singleton VMs (gui-vm, net-vm, etc.), App VMs are instantiated multiple times.
# Each instance is configured via hostConfig.appvm which contains:
#   - name: VM name (e.g., "chromium", "comms")
#   - ramMb, cores: Resource allocation
#   - applications: List of apps with name, command, packages, etc.
#   - packages: Additional packages for the VM
#   - vtpm, waypipe, ghafAudio: Feature flags
#   - extraModules: Additional modules for this specific appvm
#
# Extensions Pattern:
#   Features that need to add applications (like ghaf-intro) use the `extensions` option
#   at host level. Extensions are applied via NixOS native extendModules and can set
#   ghaf.appvm.applications to add apps that merge with the base apps.
#
# Usage:
#   mkAppVm = vmDef: lib.nixosSystem {
#     modules = [ inputs.self.nixosModules.appvm-base ];
#     specialArgs = lib.ghaf.vm.mkSpecialArgs {
#       inherit lib inputs;
#       globalConfig = hostGlobalConfig;
#       hostConfig = (lib.ghaf.vm.mkHostConfig { ... }) // { appvm = vmDef; };
#     };
#   };
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
  # Get VM definition from hostConfig
  vm = hostConfig.appvm;
  vmName = "${vm.name}-vm";

  # Helper to unwrap mkDefault values for use in lib.mkIf conditions
  # Values like `lib.mkDefault true` become { _type = "override"; content = true; priority = 1000; }
  # This extracts the actual boolean for use in conditionals
  unwrap = val: if val._type or null == "override" then val.content else val;

  # Base applications from hostConfig (defined in mkAppVm call)
  baseApplications = vm.applications or [ ];
  # Packages from base applications (computed at import time)
  baseAppPackages = builtins.concatLists (map (app: app.packages or [ ]) baseApplications);
  # Extra modules from base applications (flattened) - imported at module load time
  baseAppExtraModules = builtins.concatLists (map (app: app.extraModules or [ ]) baseApplications);

  # Yubikey CTAP proxy support
  yubiPackages = lib.optional (vm.yubiProxy or false) pkgs.qubes-ctap;

  sharedVmDirectory =
    hostConfig.sharedVmDirectory or {
      enable = false;
      vms = [ ];
    };
in
{
  _file = ./appvm-base.nix;

  imports = [
    inputs.preservation.nixosModules.preservation
    inputs.self.nixosModules.givc
    inputs.self.nixosModules.hardware-x86_64-guest-kernel
    inputs.self.nixosModules.vm-modules
    inputs.self.nixosModules.profiles
  ]
  # Import base application extraModules (from mkAppVm call)
  ++ baseAppExtraModules
  # Import VM-level extraModules
  ++ (vm.extraModules or [ ]);

  options.ghaf.appvm = {
    # Applications option for extensions to add apps
    # Extensions use: ghaf.appvm.applications = [{ name = "..."; ... }];
    applications = lib.mkOption {
      type = lib.types.listOf lib.types.attrs;
      default = [ ];
      description = ''
        Additional applications added via extensions.
        These are merged with base applications from mkAppVm.
        Use this in extensions to add apps to an AppVM.

        Note: Extension applications' extraModules should be added
        directly as part of the extension module, not via app.extraModules.
      '';
    };

    # Export vmDef so host can read values from evaluatedConfig.config.ghaf.appvm.vmDef
    # This includes merged applications from both base and extensions
    vmDef = lib.mkOption {
      type = lib.types.attrs;
      readOnly = true;
      description = "The VM definition with merged applications. Exposed for host-side access.";
    };
  };

  config =
    let
      # All applications = base (from mkAppVm) + extensions (from ghaf.appvm.applications)
      allApplications = baseApplications ++ config.ghaf.appvm.applications;

      # Process applications for GIVC
      givcApps = map (app: {
        name = app.givcName or (lib.strings.toLower (lib.replaceStrings [ " " ] [ "-" ] app.name));
        command = "${config.ghaf.givc.appPrefix}/run-waypipe ${config.ghaf.givc.appPrefix}/${app.command}";
        args = app.givcArgs or [ ];
      }) allApplications;

      # Packages from extension applications
      extAppPackages = builtins.concatLists (
        map (app: app.packages or [ ]) config.ghaf.appvm.applications
      );
    in
    {
      # Set vmDef with merged applications and unwrapped vtpm values
      # vtpm values use mkDefault which wraps them - unwrap for host-side access
      ghaf.appvm.vmDef = vm // {
        applications = allApplications;
        vtpm = {
          enable = unwrap (vm.vtpm.enable or false);
          runInVM = unwrap (vm.vtpm.runInVM or false);
          basePort = vm.vtpm.basePort or null;
        };
      };

      ghaf = {
        # Common namespace - from hostConfig (for appHosts, systemHosts, etc.)
        common = hostConfig.common or { };

        # GIVC configuration - from globalConfig
        givc = {
          enable = globalConfig.givc.enable or false;
          debug = globalConfig.givc.debug or false;
        };
        givc.appvm = {
          enable = true;
          applications = givcApps;
        };

        # User configuration
        users.appUser = {
          enable = true;
          extraGroups = [
            "audio"
            "video"
            "users"
            "plugdev"
          ];
        };

        # Profiles - from globalConfig
        profiles.debug.enable = lib.mkDefault (globalConfig.debug.enable or false);

        development = {
          ssh.daemon.enable = lib.mkDefault (globalConfig.development.ssh.daemon.enable or false);
          debug.tools.enable = lib.mkDefault (globalConfig.development.debug.tools.enable or false);
          nix-setup.enable = lib.mkDefault (globalConfig.development.nix-setup.enable or false);
        };

        # System
        type = "app-vm";

        systemd = {
          enable = true;
          withName = "appvm-systemd";
          withLocaled = true;
          withNss = true;
          withResolved = true;
          withTimesyncd = true;
          withPolkit = true;
          withDebug = globalConfig.debug.enable or false;
          withHardenedConfigs = true;
        };

        # Enable dynamic hostname export for AppVMs
        identity.vmHostNameExport.enable = true;

        # Storage - from globalConfig
        storagevm = {
          enable = true;
          name = vmName;
          directories =
            lib.optionals
              (!lib.hasAttr "${config.ghaf.users.appUser.name}" (config.ghaf.storagevm.users or { }))
              [
                # By default, persist appuser's entire home directory unless overwritten
                {
                  directory = "/home/${config.ghaf.users.appUser.name}";
                  user = "${config.ghaf.users.appUser.name}";
                  group = "${config.ghaf.users.appUser.name}";
                  mode = "0700";
                }
              ];
          shared-folders.enable =
            (sharedVmDirectory.enable or false) && builtins.elem vmName (sharedVmDirectory.vms or [ ]);
          encryption.enable = globalConfig.storage.encryption.enable or false;
        };

        # Networking
        virtualization.microvm.vm-networking = {
          enable = true;
          inherit vmName;
        };
        # vTPM support
        virtualization.microvm.tpm.emulated = {
          enable = vm.vtpm.enable or false;
          runInVM = vm.vtpm.runInVM or false;
          inherit (vm) name;
        };

        # Waypipe support
        waypipe = {
          enable = vm.waypipe.enable or true;
          inherit vm;
          vmCid = hostConfig.networking.thisVm.cid or 0;
          guivmCid = hostConfig.networking.hosts."gui-vm".cid or 3;
        }
        // lib.optionalAttrs (globalConfig.shm.enable or false) {
          serverSocketPath = globalConfig.shm.serverSocketPath or "";
        };

        # Audio client
        services.audio = lib.mkIf (unwrap (vm.ghafAudio.enable or false)) {
          enable = true;
          role = "client";
        };

        # Logging - from globalConfig
        logging = {
          inherit (globalConfig.logging) enable listener;
          client.enable = globalConfig.logging.enable or false;
        };

        # Security
        security.fail2ban.enable = globalConfig.development.ssh.daemon.enable or false;
      };

      # Combined udev rules (yubikey + passthrough)
      services.udev.extraRules =
        # Yubikey CTAP proxy rules
        (lib.optionalString (vm.yubiProxy or false) ''
          ACTION=="remove", GOTO="qctap_hidraw_end"
          SUBSYSTEM=="hidraw", MODE="0660", GROUP="users"
          LABEL="qctap_hidraw_end"
        '')
        # Passthrough udev rules
        + (hostConfig.passthrough.vmUdevExtraRules or "");

      # Yubikey CTAP proxy service
      systemd.services.ctapproxy = lib.mkIf (vm.yubiProxy or false) {
        enable = true;
        description = "CTAP Proxy";
        serviceConfig = {
          ExecStartPre = "${pkgs.coreutils}/bin/mkdir -p /var/log/qubes";
          ExecStart = "${pkgs.qubes-ctap}/bin/qctap-proxy --qrexec ${
            pkgs.writeShellApplication {
              name = "qrexec-client-vm";
              runtimeInputs = [ pkgs.givc-cli ];
              text = ''
                shift
                exec givc-cli ${hostConfig.givc.cliArgs or ""} ctap "$@"
              '';
            }
          }/bin/qrexec-client-vm dummy";
          Type = "notify";
          KillMode = "process";
        };
        wantedBy = [ "multi-user.target" ];
      };

      system.stateVersion = lib.trivial.release;

      # Allow runtime timezone changes via GIVC set-timezone.
      time.timeZone = null;

      nixpkgs = {
        buildPlatform.system = globalConfig.platform.buildSystem or "x86_64-linux";
        hostPlatform.system = globalConfig.platform.hostSystem or "x86_64-linux";
      };

      environment.systemPackages = [
        pkgs.opensc
        pkgs.givc-cli
      ]
      ++ (vm.packages or [ ])
      ++ baseAppPackages
      ++ extAppPackages
      ++ yubiPackages;

      security.pki.certificateFiles = lib.mkIf (globalConfig.idsvm.mitmproxy.enable or false) [
        ./idsvm/mitmproxy/mitmproxy-ca/mitmproxy-ca-cert.pem
      ];

      microvm = {
        optimize.enable = false;
        # Sensible defaults based on vm definition - can be further overridden via vmConfig
        mem = lib.mkDefault ((vm.ramMb or 4096) * ((vm.balloonRatio or 2) + 1));
        balloon = (vm.balloonRatio or 2) > 0;
        deflateOnOOM = false;
        vcpu = lib.mkDefault (vm.cores or 4);
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
            "-M"
            "accel=kvm:tcg,mem-merge=on,sata=off"
            "-device"
            "vhost-vsock-pci,guest-cid=${toString (hostConfig.networking.thisVm.cid or 100)}"
            "-device"
            "qemu-xhci"
          ]
          ++ (hostConfig.passthrough.qemuExtraArgs or [ ]);

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
    };
}
