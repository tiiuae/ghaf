# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# GUI VM Configuration Module
#
# This module uses the globalConfig pattern:
# - Global settings (debug, development, logging, storage, givc) come via globalConfig specialArg
# - Host-specific settings (networking.hosts, users, appvms) come via hostConfig specialArg
#
# The VM configuration is self-contained and does not reference `configHost`.
{
  config,
  lib,
  inputs,
  ...
}:
let
  vmName = "gui-vm";
  hostGlobalConfig = config.ghaf.global-config;

  inherit (lib) rmDesktopEntries;
  guivmBaseConfiguration = {
    _file = ./guivm.nix;
    imports = [
      inputs.self.nixosModules.profiles
      inputs.self.nixosModules.givc
      inputs.self.nixosModules.hardware-x86_64-guest-kernel
      inputs.preservation.nixosModules.preservation
      inputs.self.nixosModules.vm-modules

      (
        {
          lib,
          pkgs,
          globalConfig,
          hostConfig,
          ...
        }:
        let
          # A list of applications from all AppVMs (accessed via hostConfig)
          enabledVms = lib.filterAttrs (_: vm: vm.enable) hostConfig.appvms;
          virtualApps = lib.lists.concatMap (
            vm: map (app: app // { vmName = "${vm.name}-vm"; }) vm.applications
          ) (lib.attrsets.mapAttrsToList (name: vm: { inherit name; } // vm) enabledVms);

          # Launchers for all virtualized applications that run in AppVMs
          virtualLaunchers = map (app: rec {
            inherit (app) name;
            inherit (app) description;
            vm = app.vmName;
            # Use givc settings from globalConfig
            execPath = "${pkgs.givc-cli}/bin/givc-cli ${hostConfig.givc.cliArgs} start app --vm ${vm} ${app.givcName}";
            inherit (app) icon;
          }) virtualApps;

          # Launchers for all desktop, non-virtualized applications that run in the GUIVM
          guivmLaunchers = map (app: {
            inherit (app) name;
            inherit (app) description;
            execPath = app.command;
            inherit (app) icon;
          }) cfg.applications;
        in
        {
          imports = [
            #TODO: inception cross reference. FIX: this
            ../../reference/services
          ];

          ghaf = {
            # Profiles - from globalConfig
            profiles = {
              debug.enable = lib.mkDefault globalConfig.debug.enable;
              graphics.enable = true;
            };

            users = {
              adUsers = {
                inherit (hostConfig.users.profile.ad-users) enable;
              };
              homedUser = {
                inherit (hostConfig.users.profile.homed-user) enable;
                fidoAuth = true;
              };
            };

            development = {
              ssh.daemon.enable = lib.mkDefault globalConfig.development.ssh.daemon.enable;
              debug.tools.enable = lib.mkDefault globalConfig.development.debug.tools.enable;
              debug.tools.gui.enable = lib.mkDefault globalConfig.development.debug.tools.enable;
              nix-setup.enable = lib.mkDefault globalConfig.development.nix-setup.enable;
            };

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
              withDebug = globalConfig.debug.enable;
              withHardenedConfigs = true;
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
              encryption.enable = globalConfig.storage.encryption.enable;
            };

            # Networking
            virtualization.microvm.vm-networking = {
              enable = true;
              inherit vmName;
            };

            virtualization.microvm.tpm.passthrough = {
              inherit (globalConfig.storage.encryption) enable;
              rootNVIndex = "0x81703000";
            };

            # Create launchers for regular apps running in the GUIVM and virtualized ones if GIVC is enabled
            graphics = {
              boot = {
                enable = true; # Enable graphical boot on gui-vm
                renderer = "gpu"; # Use GPU for graphical boot in gui-vm
              };
              launchers = guivmLaunchers ++ lib.optionals globalConfig.givc.enable virtualLaunchers;
              cosmic = {
                securityContext.rules = map (vm: {
                  identifier = vm.name;
                  color = vm.borderColor;
                }) (lib.attrsets.mapAttrsToList (name: vm: { inherit name; } // vm) enabledVms);
              };
            };

            # Logging
            logging = {
              inherit (globalConfig.logging) enable listener;
              client.enable = globalConfig.logging.enable;
            };

            # Services
            services = {
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

            security.fail2ban.enable = globalConfig.development.ssh.daemon.enable;
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
                  if hostConfig.users.homedUser.enable then
                    "${toString hostConfig.users.homedUser.uid}"
                  else
                    "${toString hostConfig.users.admin.uid}";
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
              ++ lib.optional globalConfig.debug.enable pkgs.givc-cli
              # Packages for checking hardware acceleration
              ++ lib.optionals globalConfig.debug.enable [
                pkgs.mesa-demos
                pkgs.libva-utils
                pkgs.glib
              ]
              ++ [ pkgs.vhotplug ];
            sessionVariables = lib.optionalAttrs globalConfig.debug.enable (
              {
                GIVC_NAME = "admin-vm";
                GIVC_ADDR = hostConfig.networking.hosts."admin-vm".ipv4;
                GIVC_PORT = "9001";
              }
              // lib.optionalAttrs hostConfig.givc.enableTls {
                GIVC_CA_CERT = "/run/givc/ca-cert.pem";
                GIVC_HOST_CERT = "/run/givc/cert.pem";
                GIVC_HOST_KEY = "/run/givc/key.pem";
              }
            );
          };

          time.timeZone = globalConfig.platform.timeZone;
          system.stateVersion = lib.trivial.release;

          nixpkgs = {
            buildPlatform.system = globalConfig.platform.buildSystem;
            hostPlatform.system = globalConfig.platform.hostSystem;
          };

          microvm = {
            optimize.enable = false;
            vcpu = 6;
            mem = 12288;
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
            ++ lib.optionals (!globalConfig.storage.storeOnDisk) [
              {
                tag = "ro-store";
                source = "/nix/store";
                mountPoint = "/nix/.ro-store";
                proto = "virtiofs";
              }
            ];

            writableStoreOverlay = lib.mkIf (!globalConfig.storage.storeOnDisk) "/nix/.rw-store";

            qemu = {
              extraArgs = [
                "-device"
                "qemu-xhci"
                "-device"
                "vhost-vsock-pci,guest-cid=${toString hostConfig.networking.thisVm.cid}"
              ];

              machine =
                {
                  # Use the same machine type as the host
                  x86_64-linux = "q35";
                  aarch64-linux = "virt";
                }
                .${globalConfig.platform.hostSystem};
            };
          }
          // lib.optionalAttrs globalConfig.storage.storeOnDisk {
            storeOnDisk = true;
            storeDiskType = "erofs";
            storeDiskErofsFlags = [
              "-zlz4hc"
              "-Eztailpacking"
            ];
          };
        }
      )
    ];
  };

  cfg = config.ghaf.virtualization.microvm.guivm;
in
{
  options.ghaf.virtualization.microvm.guivm = {
    enable = lib.mkEnableOption "GUIVM";

    evaluatedConfig = lib.mkOption {
      type = lib.types.nullOr lib.types.unspecified;
      default = null;
      description = ''
        Pre-evaluated GUI VM configuration from extendModules.
        When set, this takes precedence over the legacy guivmBaseConfiguration.
        Profiles should set this by extending guivmBase from laptop-x86 profile.
      '';
    };

    extraModules = lib.mkOption {
      type = lib.types.listOf lib.types.deferredModule;
      description = ''
        List of additional modules to be imported and evaluated as part of
        GUIVM's NixOS configuration.

        NOTE: When using evaluatedConfig (recommended), ensure your profile
        includes these extraModules in its extendModules call. Example:

          guivm.evaluatedConfig = guivmBase.extendModules {
            modules = [ ... ] ++ config.ghaf...guivm.extraModules;
          };
      '';
      default = [ ];
    };
    extraNetworking = lib.mkOption {
      type = lib.types.networking;
      description = "Extra Networking option";
      default = { };
    };
    applications = lib.mkOption {
      description = ''
        Applications to include in the GUIVM
      '';
      type = lib.types.listOf (
        lib.types.submodule {
          options = {
            name = lib.mkOption {
              type = lib.types.str;
              description = "The name of the application";
            };
            description = lib.mkOption {
              type = lib.types.str;
              description = "A brief description of the application";
            };
            icon = lib.mkOption {
              type = lib.types.str;
              description = "Application icon";
              default = null;
            };
            command = lib.mkOption {
              type = lib.types.str;
              description = "The command to run the application";
              default = null;
            };
          };
        }
      );
      default = [ ];
    };
  };
  config = lib.mkIf cfg.enable {
    # Warning if extraModules set but profile might not include them
    warnings = lib.optionals (cfg.evaluatedConfig != null && cfg.extraModules != [ ]) [
      ''
        ghaf.virtualization.microvm.guivm.extraModules is non-empty but evaluatedConfig is set.
        Ensure your profile includes extraModules in its extendModules call:
          guivm.evaluatedConfig = guivmBase.extendModules {
            modules = [ ... ] ++ config.ghaf.virtualization.microvm.guivm.extraModules;
          };
      ''
    ];

    ghaf.common.extraNetworking.hosts.${vmName} = cfg.extraNetworking;

    microvm.vms."${vmName}" =
      if cfg.evaluatedConfig != null then
        # New path: Use pre-evaluated config from profile (via extendModules)
        {
          autostart = !config.ghaf.microvm-boot.enable;
          inherit (inputs) nixpkgs;
          inherit (cfg) evaluatedConfig;
        }
      else
        # Legacy path: Build config inline (for non-laptop targets)
        {
          autostart = !config.ghaf.microvm-boot.enable;
          inherit (inputs) nixpkgs;

          # Use mkVmSpecialArgs for globalConfig + hostConfig
          specialArgs = lib.ghaf.mkVmSpecialArgs {
            inherit lib inputs;
            globalConfig = hostGlobalConfig;
            hostConfig = lib.ghaf.mkVmHostConfig {
              inherit config vmName;
            };
          };

          config = guivmBaseConfiguration // {
            imports = guivmBaseConfiguration.imports ++ cfg.extraModules;
          };
        };
  };
}
