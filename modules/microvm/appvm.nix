# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# App VM Module - Uses evaluatedConfig pattern for composability
#
# This module creates app VMs using lib.nixosSystem + extendModules,
# enabling clean composition and downstream extensibility.
# - self and inputs come from specialArgs (no currying)
#
{
  config,
  lib,
  pkgs,
  self,
  inputs,
  ...
}:
let
  cfg = config.ghaf.virtualization.microvm.appvm;

  inherit (lib)
    mkEnableOption
    mkOption
    types
    optionalAttrs
    ;
  inherit (config.ghaf.virtualization.microvm-host) sharedVmDirectory;

  # Use flake export - self.lib.vmBuilders
  mkAppVm = self.lib.vmBuilders.mkAppVm { inherit inputs lib; };

  # Get sharedSystemConfig from specialArgs (set by target builders)
  # Provides an empty default for targets that don't use VMs (assertion checks when enabled)
  sharedSystemConfig = config._module.specialArgs.sharedSystemConfig or { };
  systemConfigModule = sharedSystemConfig;

  # Capture host values needed for host bindings
  # IMPORTANT: Capture these BEFORE the makeVm function to avoid closure issues
  hostValues = {
    inherit (config.ghaf.virtualization.microvm) storeOnDisk;
    storageEncryptionEnable = config.ghaf.virtualization.storagevm-encryption.enable;
    mitmproxyEnable = config.ghaf.virtualization.microvm.idsvm.mitmproxy.enable or false;
    buildPlatformSystem = config.nixpkgs.buildPlatform.system;
    hostPlatformSystem = config.nixpkgs.hostPlatform.system;
    microvmBootEnable = config.ghaf.microvm-boot.enable;
    sharedVmDirectoryEnable = sharedVmDirectory.enable;
    sharedVmDirectoryVms = sharedVmDirectory.vms;
    shmEnable = config.ghaf.shm.enable or false;
    shmServerSocketPath = config.ghaf.shm.serverSocketPath or "";
    networkingHosts = config.ghaf.networking.hosts;
    qemuExtraArgs = config.ghaf.hardware.passthrough.qemuExtraArgs or { };
    vmUdevExtraRules = config.ghaf.hardware.passthrough.vmUdevExtraRules or { };
    givcAppPrefix = config.ghaf.givc.appPrefix;
    givcCliArgs = config.ghaf.givc.cliArgs;
    loggingEnable = config.ghaf.logging.enable;
    sshDaemonEnable = config.ghaf.development.ssh.daemon.enable;
    # Logging config - pass to all app VMs
    loggingListenerAddress = config.ghaf.logging.listener.address or "";
    loggingServerEndpoint = config.ghaf.logging.server.endpoint or "";
  };

  # Common namespace from host - passed to all app VMs
  commonModule = {
    config.ghaf = {
      inherit (config.ghaf) common;
    };
  };

  makeVm =
    { vm }:
    let
      vmName = "${vm.name}-vm";
      # A list of applications for the GIVC service
      givcApplications = map (app: {
        name = app.givcName;
        command = "${hostValues.givcAppPrefix}/run-waypipe ${hostValues.givcAppPrefix}/${app.command}";
        args = app.givcArgs;
      }) vm.applications;
      # Packages and extra modules from all applications defined in the appvm
      appPackages = builtins.concatLists (map (app: app.packages) vm.applications);
      appExtraModules = builtins.concatLists (map (app: app.extraModules) vm.applications);
      yubiPackages = lib.optional vm.yubiProxy pkgs.qubes-ctap;
      yubiExtra = lib.optional vm.yubiProxy {
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
                  exec givc-cli ${hostValues.givcCliArgs} ctap "$@"
                '';
              }
            }/bin/qrexec-client-vm dummy";
            Type = "notify";
            KillMode = "process";
          };
          wantedBy = [ "multi-user.target" ];
        };
      };

      # Create the base app VM configuration
      baseAppVm = mkAppVm {
        system = hostValues.hostPlatformSystem;
        inherit
          vm
          givcApplications
          appPackages
          yubiPackages
          appExtraModules
          yubiExtra
          systemConfigModule
          ;
        inherit (cfg) extraModules;
      };

      # Host-specific bindings (values that MUST come from the host)
      hostBindings = {
        # Platform settings (cross-compilation support)
        nixpkgs.buildPlatform.system = hostValues.buildPlatformSystem;

        # Storage encryption
        ghaf.storagevm = {
          shared-folders.enable =
            hostValues.sharedVmDirectoryEnable && builtins.elem vmName hostValues.sharedVmDirectoryVms;
          encryption.enable = hostValues.storageEncryptionEnable;
        };

        # Logging - pass host logging config to VM
        ghaf.logging = {
          client.enable = hostValues.loggingEnable;
          listener.address = hostValues.loggingListenerAddress;
          server.endpoint = hostValues.loggingServerEndpoint;
        };

        # Security
        ghaf.security.fail2ban.enable = hostValues.sshDaemonEnable;

        # Waypipe SHM settings
        ghaf.waypipe = optionalAttrs hostValues.shmEnable {
          inherit (hostValues) shmServerSocketPath;
        };

        # Certificate files for mitmproxy
        security.pki.certificateFiles = lib.mkIf hostValues.mitmproxyEnable [
          ./sysvms/idsvm/mitmproxy/mitmproxy-ca/mitmproxy-ca-cert.pem
        ];

        # Store configuration
        microvm = {
          shares = lib.optionals (!hostValues.storeOnDisk) [
            {
              tag = "ro-store";
              source = "/nix/store";
              mountPoint = "/nix/.ro-store";
              proto = "virtiofs";
            }
          ];

          writableStoreOverlay = lib.mkIf (!hostValues.storeOnDisk) "/nix/.rw-store";

          qemu = {
            extraArgs = [
              "-M"
              "accel=kvm:tcg,mem-merge=on,sata=off"
              "-device"
              "vhost-vsock-pci,guest-cid=${toString hostValues.networkingHosts."${vmName}".cid}"
            ]
            ++ lib.optionals (lib.hasAttr vmName hostValues.qemuExtraArgs) hostValues.qemuExtraArgs.${vmName};

            machine =
              {
                x86_64-linux = "q35";
                aarch64-linux = "virt";
              }
              .${hostValues.hostPlatformSystem};
          };
        }
        // lib.optionalAttrs hostValues.storeOnDisk {
          storeOnDisk = true;
          storeDiskType = "erofs";
          storeDiskErofsFlags = [
            "-zlz4hc"
            "-Eztailpacking"
          ];
        };

        # Udev rules from passthrough
        services.udev = lib.mkIf (lib.hasAttr vmName hostValues.vmUdevExtraRules) {
          extraRules = lib.concatStringsSep "\n" hostValues.vmUdevExtraRules.${vmName};
        };
      };
    in
    {
      autostart = !hostValues.microvmBootEnable;

      # Use evaluatedConfig with extendModules for composability
      evaluatedConfig = baseAppVm.extendModules {
        modules = [
          hostBindings
          commonModule
        ]
        ++ vm.extraModules;
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
        name: _vm: config.microvm.vms."${name}-vm".evaluatedConfig.config.ghaf.waypipe.enable
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
      # Assert that sharedSystemConfig is provided when VM is enabled
      assertions = [
        {
          assertion = sharedSystemConfig != { };
          message = "AppVM requires sharedSystemConfig to be provided via specialArgs. Update your target builder to provide sharedSystemConfig.";
        }
      ];

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
            "vsockproxy-${name}-vm" =
              config.microvm.vms."${name}-vm".evaluatedConfig.config.ghaf.waypipe.proxyService;
          }) (builtins.attrNames vmsWithWaypipe);
        in
        lib.foldr lib.recursiveUpdate { } (swtpms ++ proxyServices);

      # GUIVM needs to have a dedicated waypipe instance for each AppVM
      ghaf.virtualization.microvm.extensions.guivm = [
        {
          systemd.user.services = lib.mapAttrs' (name: _: {
            name = "waypipe-${name}-vm";
            value = config.microvm.vms."${name}-vm".evaluatedConfig.config.ghaf.waypipe.waypipeService;
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
