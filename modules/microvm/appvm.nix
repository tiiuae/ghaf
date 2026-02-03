# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# App VM Configuration Module
#
# This module uses the globalConfig pattern:
# - Global settings (debug, development, logging, storage, givc) come via globalConfig specialArg
# - Host-specific settings (passthrough, networking, microvmBoot) come via hostConfig specialArg
#
{
  config,
  lib,
  pkgs,
  inputs,
  ...
}:
let
  cfg = config.ghaf.virtualization.microvm.appvm;
  hostGlobalConfig = config.ghaf.global-config;

  inherit (lib)
    mkEnableOption
    mkOption
    types
    optionalAttrs
    ;
  inherit (config.ghaf.virtualization.microvm-host) sharedVmDirectory;

  makeVm =
    { vm }:
    let
      vmName = "${vm.name}-vm";

      # Create hostConfig for this specific VM
      vmHostConfig = lib.ghaf.mkVmHostConfig {
        inherit config vmName;
      };

      # A list of applications for the GIVC service (uses inner config.ghaf.givc.appPrefix)

      # Packages and extra modules from all applications defined in the appvm
      appPackages = builtins.concatLists (map (app: app.packages) vm.applications);
      appExtraModules = builtins.concatLists (map (app: app.extraModules) vm.applications);
      yubiPackages = lib.optional vm.yubiProxy pkgs.qubes-ctap;
      yubiExtra = lib.optional vm.yubiProxy (
        { pkgs, hostConfig, ... }:
        {
          services.udev.extraRules = ''
            ACTION=="remove", GOTO="qctap_hidraw_end"
            SUBSYSTEM=="hidraw", MODE="0660", GROUP="users"
            LABEL="qctap_hidraw_end"
          '';
          systemd.services.ctapproxy = {
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
                    exec givc-cli ${hostConfig.givc.cliArgs} ctap "$@"
                  '';
                }
              }/bin/qrexec-client-vm dummy";
              Type = "notify";
              KillMode = "process";
            };
            wantedBy = [ "multi-user.target" ];
          };
        }
      );

      appvmConfiguration = {
        _file = ./appvm.nix;
        imports = [
          inputs.preservation.nixosModules.preservation
          inputs.self.nixosModules.givc
          inputs.self.nixosModules.hardware-x86_64-guest-kernel
          inputs.self.nixosModules.vm-modules
          inputs.self.nixosModules.profiles
          (
            {
              lib,
              config,
              pkgs,
              globalConfig,
              hostConfig,
              ...
            }:
            let
              # Build givcApplications using inner config for appPrefix
              givcApps = map (app: {
                name = app.givcName;
                command = "${config.ghaf.givc.appPrefix}/run-waypipe ${config.ghaf.givc.appPrefix}/${app.command}";
                args = app.givcArgs;
              }) vm.applications;
            in
            {
              ghaf = {
                givc.appvm = {
                  enable = true;
                  applications = givcApps;
                };

                # Profiles
                users.appUser = {
                  enable = true;
                  extraGroups = [
                    "audio"
                    "video"
                    "users"
                    "plugdev"
                  ];
                };

                profiles.debug.enable = lib.mkDefault globalConfig.debug.enable;
                development = {
                  ssh.daemon.enable = lib.mkDefault globalConfig.development.ssh.daemon.enable;
                  debug.tools.enable = lib.mkDefault globalConfig.development.debug.tools.enable;
                  nix-setup.enable = lib.mkDefault globalConfig.development.nix-setup.enable;
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
                  withDebug = globalConfig.debug.enable;
                  withHardenedConfigs = true;
                };

                # Storage
                storagevm = {
                  enable = true;
                  name = vmName;
                  directories =
                    lib.optionals (!lib.hasAttr "${config.ghaf.users.appUser.name}" config.ghaf.storagevm.users)
                      [
                        # By default, persist appusers entire home directory unless overwritten by defining
                        # either storagevm.users.<user>.directories and/or .files explicitly in an appvm.
                        {
                          directory = "/home/${config.ghaf.users.appUser.name}";
                          user = "${config.ghaf.users.appUser.name}";
                          group = "${config.ghaf.users.appUser.name}";
                          mode = "0700";
                        }
                      ];
                  shared-folders.enable = sharedVmDirectory.enable && builtins.elem vmName sharedVmDirectory.vms;
                  encryption.enable = globalConfig.storage.encryption.enable;
                };

                # Networking
                virtualization.microvm.vm-networking = {
                  enable = true;
                  inherit vmName;
                };

                virtualization.microvm.tpm.emulated = {
                  inherit (vm.vtpm) enable runInVM;
                  inherit (vm) name;
                };

                # Services
                waypipe = {
                  inherit (vm.waypipe) enable;
                  inherit vm;
                }
                // optionalAttrs globalConfig.shm.enable {
                  inherit (globalConfig.shm) serverSocketPath;
                };

                services.audio = lib.mkIf vm.ghafAudio.enable {
                  enable = true;
                  role = "client";
                };

                logging = {
                  inherit (globalConfig.logging) enable listener;
                  client.enable = globalConfig.logging.enable;
                };

                security.fail2ban.enable = globalConfig.development.ssh.daemon.enable;

                # Enable dynamic hostname export for AppVMs
                identity.vmHostNameExport.enable = true;

              };

              system.stateVersion = lib.trivial.release;

              nixpkgs = {
                buildPlatform.system = globalConfig.platform.buildSystem;
                hostPlatform.system = globalConfig.platform.hostSystem;
              };

              environment.systemPackages = [
                pkgs.opensc
                pkgs.givc-cli
              ]
              ++ vm.packages
              ++ appPackages
              ++ yubiPackages;

              security.pki.certificateFiles = lib.mkIf globalConfig.idsvm.mitmproxy.enable [
                ./sysvms/idsvm/mitmproxy/mitmproxy-ca/mitmproxy-ca-cert.pem
              ];

              time.timeZone = globalConfig.platform.timeZone;

              microvm = {
                optimize.enable = false;
                mem = vm.ramMb * (vm.balloonRatio + 1);
                balloon = vm.balloonRatio > 0;
                deflateOnOOM = false;
                vcpu = vm.cores;
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
                    "-M"
                    "accel=kvm:tcg,mem-merge=on,sata=off"
                    "-device"
                    "vhost-vsock-pci,guest-cid=${toString hostConfig.networking.thisVm.cid}"
                    "-device"
                    "qemu-xhci"
                  ]
                  ++ hostConfig.passthrough.qemuExtraArgs;

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

              services.udev = lib.mkIf (hostConfig.passthrough.vmUdevExtraRules != "") {
                extraRules = hostConfig.passthrough.vmUdevExtraRules;
              };
            }
          )
        ];
      };
    in
    {
      autostart = !vmHostConfig.microvmBoot.enable;
      inherit (inputs) nixpkgs;

      # Use mkVmSpecialArgs for globalConfig + hostConfig
      specialArgs = lib.ghaf.mkVmSpecialArgs {
        inherit lib inputs;
        globalConfig = hostGlobalConfig;
        hostConfig = vmHostConfig;
      };

      config = appvmConfiguration // {
        imports =
          appvmConfiguration.imports ++ cfg.extraModules ++ vm.extraModules ++ yubiExtra ++ appExtraModules;
      };
    };
in
{
  options.ghaf.virtualization.microvm.appvm = {
    enable = lib.mkEnableOption "appvm";
    vms = mkOption {
      description = ''
        List of AppVMs to be created
      '';
      type = types.attrsOf (
        types.submodule {
          options = {
            enable = lib.mkEnableOption "this virtual machine";
            applications = mkOption {
              description = ''
                Applications to include in the AppVM
              '';
              type = types.listOf (
                types.submodule (
                  { config, lib, ... }:
                  {
                    options = {
                      name = mkOption {
                        type = types.str;
                        description = "The name of the application";
                      };
                      description = mkOption {
                        type = types.str;
                        description = "A brief description of the application";
                      };
                      packages = mkOption {
                        type = types.listOf types.package;
                        description = "A list of packages required for the application";
                        default = [ ];
                      };
                      icon = mkOption {
                        type = types.str;
                        description = "Application icon";
                        default = null;
                      };
                      command = mkOption {
                        type = types.str;
                        description = "The command to run the application";
                        default = null;
                      };
                      extraModules = mkOption {
                        description = "Additional modules required for the application";
                        type = types.listOf types.attrs;
                        default = [ ];
                      };
                      givcName = mkOption {
                        description = "GIVC name for the application";
                        type = types.str;
                      };
                      givcArgs = mkOption {
                        description = "A list of GIVC arguments for the application";
                        type = types.listOf types.str;
                        default = [ ];
                      };
                    };
                    config = {
                      # Create a default GIVC name for the application
                      givcName = lib.mkDefault (lib.strings.toLower (lib.replaceStrings [ " " ] [ "-" ] config.name));
                    };
                  }
                )
              );
              default = [ ];
            };
            packages = mkOption {
              description = ''
                Packages that are included into the AppVM
              '';
              type = types.listOf types.package;
              default = [ ];
            };
            extraNetworking = lib.mkOption {
              type = types.networking;
              description = "Extra Networking option";
              default = { };
            };
            ramMb = mkOption {
              description = ''
                Minimum amount of RAM for this AppVM
              '';
              type = types.int;
            };
            balloonRatio = mkOption {
              description = ''
                Amount of dynamic RAM for this AppVM as a multiple of ramMb
              '';
              type = types.number;
              default = 2;
            };
            cores = mkOption {
              description = ''
                Amount of processor cores for this AppVM
              '';
              type = types.int;
            };
            extraModules = mkOption {
              description = ''
                List of additional modules to be imported and evaluated as part of
                appvm's NixOS configuration.
              '';
              default = [ ];
            };
            borderColor = mkOption {
              description = ''
                Border color of the AppVM window
              '';
              type = types.nullOr types.str;
              default = null;
            };
            ghafAudio = {
              enable = lib.mkEnableOption "Ghaf application audio support";
            };
            vtpm = {
              enable = lib.mkEnableOption "vTPM support in the virtual machine";
              runInVM = mkOption {
                description = ''
                  Whether to run the swtpm instance on a separate VM or on the host.
                  If set to false, the daemon runs on the host and keys are stored on
                  the host filesystem.
                  If true, the swtpm daemon runs in the admin VM. This setup makes it
                  harder for a host process to access the guest keys.
                '';
                type = types.bool;
                default = false;
              };
              basePort = lib.mkOption {
                description = ''
                  vsock port where the remote swtpm will listen on.
                  Control channel is on <basePort> and data channel on
                  <basePort+1>.
                  Set this option when `runInVM` is `true`.
                '';
                type = types.nullOr types.int;
                default = null;
              };
            };
            waypipe.enable = mkOption {
              description = "Enable waypipe for this VM";
              type = types.bool;
              default = true;
            };
            bootPriority = mkOption {
              description = ''
                Boot priority of the AppVM.
              '';
              type = types.enum [
                "low"
                "medium"
                "high"
              ];
              default = "medium";
            };
            usbPassthrough = mkOption {
              description = ''
                List of USB passthrough rules for this AppVM
              '';
              default = [ ];
            };
            yubiProxy = mkEnableOption "2FA token proxy";
          };
        }
      );
      default = { };
    };

    extraModules = mkOption {
      description = ''
        List of additional modules to be imported and evaluated as part of
        appvm's NixOS configuration.
      '';
      default = [ ];
    };
  };

  config =
    let
      vms = lib.filterAttrs (_: vm: vm.enable) cfg.vms;
      vmsWithWaypipe = lib.filterAttrs (
        name: _vm: config.microvm.vms."${name}-vm".config.config.ghaf.waypipe.enable
      ) vms;

      makeSwtpmService =
        name: vm:
        let
          swtpmScript = pkgs.writeShellApplication {
            name = "${name}-swtpm";
            runtimeInputs = with pkgs; [
              coreutils
              swtpm
            ];
            text = ''
              mkdir -p /var/lib/swtpm/${name}/state
              swtpm socket --tpmstate dir=/var/lib/swtpm/${name}/state \
                --ctrl type=unixio,path=/var/lib/swtpm/${name}/sock \
                --tpm2 \
                --log level=20
            '';
          };
        in
        lib.mkIf (vm.vtpm.enable && !vm.vtpm.runInVM) {
          enable = true;
          description = "swtpm service for ${name}";
          path = [ swtpmScript ];
          wantedBy = [ "local-fs.target" ];
          after = [ "local-fs.target" ];
          serviceConfig = {
            Type = "simple";
            Slice = "system-appvms-${name}.slice";
            User = "microvm";
            Restart = "always";
            StateDirectory = "swtpm/${name}";
            StandardOutput = "journal";
            StandardError = "journal";
            ExecStart = "${swtpmScript}/bin/${name}-swtpm";
            LogLevelMax = "notice";
          };
        };
    in
    lib.mkIf cfg.enable {
      # Define microvms for each AppVM configuration
      microvm.vms =
        let
          vms' = lib.attrsets.mapAttrsToList (name: vm: { inherit name; } // vm) vms;
          vms'' = map (vm: { "${vm.name}-vm" = makeVm { inherit vm; }; }) vms';
        in
        lib.foldr lib.recursiveUpdate { } vms'';

      # Apply host service dependencies, add swtpm
      systemd.services =
        let
          swtpms = lib.mapAttrsToList (name: vm: {
            "${name}-vm-swtpm" = makeSwtpmService name vm;
          }) vms;
          # Each AppVM with waypipe needs its own instance of vsockproxy on the host
          proxyServices = map (name: {
            "vsockproxy-${name}-vm" = config.microvm.vms."${name}-vm".config.config.ghaf.waypipe.proxyService;
          }) (builtins.attrNames vmsWithWaypipe);
        in
        lib.foldr lib.recursiveUpdate { } (swtpms ++ proxyServices);

      # GUIVM needs to have a dedicated waypipe instance for each AppVM
      ghaf.virtualization.microvm.guivm.extraModules = [
        {
          systemd.user.services = lib.mapAttrs' (name: _: {
            name = "waypipe-${name}-vm";
            value = config.microvm.vms."${name}-vm".config.config.ghaf.waypipe.waypipeService;
          }) vmsWithWaypipe;
        }
      ];

      ghaf.common.extraNetworking.hosts = lib.mapAttrs' (name: vm: {
        name = "${name}-vm";
        value = vm.extraNetworking or { };
      }) vms;

      # Add USB passthrough rules from AppVMs
      ghaf.hardware.passthrough.vhotplug.usbRules = lib.concatMap (vm: vm.usbPassthrough) (
        lib.attrValues vms
      );

    };
}
