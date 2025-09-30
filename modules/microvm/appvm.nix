# Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{ inputs }:
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.ghaf.virtualization.microvm.appvm;
  configHost = config;

  inherit (lib)
    mkOption
    types
    optionals
    optionalAttrs
    ;
  inherit (configHost.ghaf.virtualization.microvm-host) sharedVmDirectory;

  makeVm =
    { vm }:
    let
      vmName = "${vm.name}-vm";
      # A list of applications for the GIVC service
      givcApplications = map (app: {
        name = app.givcName;
        command = "${config.ghaf.givc.appPrefix}/run-waypipe ${config.ghaf.givc.appPrefix}/${app.command}";
        args = app.givcArgs;
      }) vm.applications;
      # Packages and extra modules from all applications defined in the appvm
      appPackages = builtins.concatLists (map (app: app.packages) vm.applications);
      appExtraModules = builtins.concatLists (map (app: app.extraModules) vm.applications);

      appvmConfiguration = {
        imports = [
          inputs.preservation.nixosModules.preservation
          inputs.self.nixosModules.givc
          inputs.self.nixosModules.vm-modules
          inputs.self.nixosModules.profiles
          {
            ghaf.givc.appvm = {
              enable = true;
              applications = givcApplications;
            };
          }
          (
            {
              lib,
              config,
              pkgs,
              ...
            }:
            {
              ghaf = {
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

                profiles.debug.enable = lib.mkDefault configHost.ghaf.profiles.debug.enable;
                development = {
                  ssh.daemon.enable = lib.mkDefault configHost.ghaf.development.ssh.daemon.enable;
                  debug.tools.enable = lib.mkDefault configHost.ghaf.development.debug.tools.enable;
                  nix-setup.enable = lib.mkDefault configHost.ghaf.development.nix-setup.enable;
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
                  withDebug = configHost.ghaf.profiles.debug.enable;
                  withHardenedConfigs = true;
                };

                # Storage
                storagevm = {
                  enable = true;
                  name = vmName;
                  users.${config.ghaf.users.appUser.name}.directories = [
                    ".config/"
                    "Downloads"
                    "Music"
                    "Pictures"
                    "Documents"
                    "Videos"
                  ];
                  shared-folders.enable = sharedVmDirectory.enable && builtins.elem vmName sharedVmDirectory.vms;
                };

                # Networking
                virtualization.microvm.vm-networking = {
                  enable = true;
                  inherit vmName;
                };

                # Services
                waypipe = {
                  inherit (vm.waypipe) enable;
                  inherit vm;
                }
                // optionalAttrs configHost.ghaf.shm.enable {
                  inherit (configHost.ghaf.shm) serverSocketPath;
                };

                ghaf-audio = {
                  inherit (vm.ghafAudio) enable;
                  inherit (vm.ghafAudio) useTunneling;
                  name = "${vm.name}";
                };
                logging.client.enable = configHost.ghaf.logging.enable;

                security.fail2ban.enable = configHost.ghaf.development.ssh.daemon.enable;

              };

              system.stateVersion = lib.trivial.release;

              nixpkgs.buildPlatform.system = configHost.nixpkgs.buildPlatform.system;
              nixpkgs.hostPlatform.system = configHost.nixpkgs.hostPlatform.system;

              environment.systemPackages = [
                pkgs.opensc
                pkgs.givc-cli
              ]
              ++ vm.packages
              ++ appPackages
              ++ optionals vm.vtpm.enable [ pkgs.tpm2-tools ];

              security.tpm2 = optionalAttrs vm.vtpm.enable {
                enable = true;
                abrmd.enable = true;
              };

              security.pki.certificateFiles =
                lib.mkIf configHost.ghaf.virtualization.microvm.idsvm.mitmproxy.enable
                  [ ./sysvms/idsvm/mitmproxy/mitmproxy-ca/mitmproxy-ca-cert.pem ];

              time.timeZone = configHost.time.timeZone;

              microvm = {
                optimize.enable = false;
                mem = vm.ramMb * (vm.balloonRatio + 1);
                balloon = vm.balloonRatio > 0;
                deflateOnOOM = false;
                vcpu = vm.cores;
                hypervisor = "qemu";
                shares = [
                  {
                    tag = "ro-store";
                    source = "/nix/store";
                    mountPoint = "/nix/.ro-store";
                    proto = "virtiofs";
                  }
                ];
                writableStoreOverlay = lib.mkIf config.ghaf.development.debug.tools.enable "/nix/.rw-store";

                qemu = {
                  extraArgs = [
                    "-M"
                    "accel=kvm:tcg,mem-merge=on,sata=off"
                    "-device"
                    "vhost-vsock-pci,guest-cid=${toString config.ghaf.networking.hosts."${vm.name}-vm".cid}"
                    "-device"
                    "qemu-xhci"
                  ]
                  ++ lib.optionals vm.vtpm.enable [
                    "-chardev"
                    "socket,id=chrtpm,path=/var/lib/swtpm/${vm.name}-sock"
                    "-tpmdev"
                    "emulator,id=tpm0,chardev=chrtpm"
                    "-device"
                    "tpm-tis,tpmdev=tpm0"
                  ]
                  ++
                    lib.optionals (lib.hasAttr "${vm.name}-vm" configHost.ghaf.hardware.passthrough.qemuExtraArgs)
                      configHost.ghaf.hardware.passthrough.qemuExtraArgs."${vm.name}-vm";

                  machine =
                    {
                      # Use the same machine type as the host
                      x86_64-linux = "q35";
                      aarch64-linux = "virt";
                    }
                    .${configHost.nixpkgs.hostPlatform.system};
                };
              };

              services.udev =
                lib.mkIf (lib.hasAttr "${vm.name}-vm" configHost.ghaf.hardware.passthrough.vmUdevExtraRules)
                  {
                    extraRules =
                      lib.concatStringsSep "\n"
                        configHost.ghaf.hardware.passthrough.vmUdevExtraRules."${vm.name}-vm";
                  };
            }
          )
        ];
      };
    in
    {
      autostart = !configHost.ghaf.microvm-boot.enable;
      inherit (inputs) nixpkgs;
      specialArgs = { inherit lib; };
      config = appvmConfiguration // {
        imports = appvmConfiguration.imports ++ cfg.extraModules ++ vm.extraModules ++ appExtraModules;
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
              useTunneling = lib.mkEnableOption "Use Pulseaudio tunneling";
            };
            vtpm.enable = lib.mkEnableOption "vTPM support in the virtual machine";
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
              mkdir -p /var/lib/swtpm/${name}-state
              swtpm socket --tpmstate dir=/var/lib/swtpm/${name}-state \
                --ctrl type=unixio,path=/var/lib/swtpm/${name}-sock \
                --tpm2 \
                --log level=20
            '';
          };
        in
        lib.mkIf vm.vtpm.enable {
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
            StateDirectory = "swtpm";
            StandardOutput = "journal";
            StandardError = "journal";
            ExecStart = "${swtpmScript}/bin/${name}-swtpm";
            LogLevelMax = "notice";
          };
        };

      vmsWithWaypipe = lib.filterAttrs (
        name: _vm: config.microvm.vms."${name}-vm".config.config.ghaf.waypipe.enable
      ) vms;

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
          serviceDependencies = lib.mapAttrsToList (name: vm: {
            "${name}-vm-swtpm" = makeSwtpmService name vm;
          }) vms;
          # Each AppVM with waypipe needs its own instance of vsockproxy on the host
          proxyServices = map (name: {
            "vsockproxy-${name}-vm" = config.microvm.vms."${name}-vm".config.config.ghaf.waypipe.proxyService;
          }) (builtins.attrNames vmsWithWaypipe);
        in
        lib.foldr lib.recursiveUpdate { } (serviceDependencies ++ proxyServices);

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

    };
}
