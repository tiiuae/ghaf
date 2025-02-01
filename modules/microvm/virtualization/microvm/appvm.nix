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
  inherit (lib) mkOption types optional;

  configHost = config;
  cfg = config.ghaf.virtualization.microvm.appvm;

  makeVm =
    { vm, vmIndex }:
    let
      vmName = "${vm.name}-vm";
      cid = if vm.cid > 0 then vm.cid else cfg.vsockBaseCID + vmIndex;
      # A list of applications for the GIVC service
      givcApplications = map (app: {
        name = app.givcName;
        command = "${config.ghaf.givc.appPrefix}/run-waypipe ${config.ghaf.givc.appPrefix}/${app.command}";
        args = app.givcArgs;
      }) vm.applications;
      # Packages and extra modules from all applications defined in the appvm
      appPackages = builtins.concatLists (map (app: app.packages) vm.applications);
      appExtraModules = builtins.concatLists (map (app: app.extraModules) vm.applications);
      sshKeysHelper = pkgs.callPackage ../../../../packages/ssh-keys-helper {
        inherit pkgs;
        config = configHost;
      };
      appvmConfiguration = {
        imports = [
          inputs.impermanence.nixosModules.impermanence
          inputs.self.nixosModules.givc-appvm
          {
            ghaf.givc.appvm = {
              enable = true;
              name = lib.mkForce vmName;
              applications = givcApplications;
            };
          }
          (import ./common/vm-networking.nix {
            inherit config lib vmName;
            inherit (vm) macAddress;
            internalIP = vmIndex + 100;
          })

          (import (./common/ghaf-audio.nix) {
            inherit configHost;
          })
          ./common/storagevm.nix
          (
            with configHost.ghaf.virtualization.microvm-host;
            lib.optionalAttrs (sharedVmDirectory.enable && builtins.elem vmName sharedVmDirectory.vms) (
              import ./common/shared-directory.nix vmName
            )
          )

          (import ./common/waypipe.nix {
            inherit
              vm
              vmIndex
              configHost
              cid
              ;
          })

          # To push logs to central location
          ../../../common/logging/client.nix
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
                  ];
                };

                profiles.debug.enable = lib.mkDefault configHost.ghaf.profiles.debug.enable;
                development = {
                  ssh.daemon.enable = lib.mkDefault configHost.ghaf.development.ssh.daemon.enable;
                  debug.tools.enable = lib.mkDefault configHost.ghaf.development.debug.tools.enable;
                  nix-setup.enable = lib.mkDefault configHost.ghaf.development.nix-setup.enable;
                };

                # Systemd
                systemd = {
                  enable = true;
                  withName = "appvm-systemd";
                  withAudit = configHost.ghaf.profiles.debug.enable;
                  withLocaled = true;
                  withNss = true;
                  withResolved = true;
                  withTimesyncd = true;
                  withPolkit = true;
                  withDebug = configHost.ghaf.profiles.debug.enable;
                  withHardenedConfigs = true;
                };

                ghaf-audio = {
                  inherit (vm.ghafAudio) enable;
                  inherit (vm.ghafAudio) useTunneling;
                  name = "${vm.name}";
                };

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
                };

                waypipe.enable = true;

                # Logging client configuration
                logging.client.enable = configHost.ghaf.logging.client.enable;
                logging.client.endpoint = configHost.ghaf.logging.client.endpoint;
              };

              # SSH is very picky about the file permissions and ownership and will
              # accept neither direct path inside /nix/store or symlink that points
              # there. Therefore we copy the file to /etc/ssh/get-auth-keys (by
              # setting mode), instead of symlinking it.
              environment.etc.${configHost.ghaf.security.sshKeys.getAuthKeysFilePathInEtc} =
                sshKeysHelper.getAuthKeysSource;
              services.openssh = configHost.ghaf.security.sshKeys.sshAuthorizedKeysCommand // {
                authorizedKeysCommandUser = config.ghaf.users.appUser.name;
              };

              system.stateVersion = lib.trivial.release;

              nixpkgs.buildPlatform.system = configHost.nixpkgs.buildPlatform.system;
              nixpkgs.hostPlatform.system = configHost.nixpkgs.hostPlatform.system;

              environment.systemPackages =
                [
                  pkgs.tpm2-tools
                  pkgs.opensc
                  pkgs.givc-cli
                ]
                ++ vm.packages
                ++ appPackages;

              security.tpm2 = {
                enable = true;
                abrmd.enable = true;
              };

              security.pki.certificateFiles =
                lib.mkIf configHost.ghaf.virtualization.microvm.idsvm.mitmproxy.enable
                  [ ./idsvm/mitmproxy/mitmproxy-ca/mitmproxy-ca-cert.pem ];

              time.timeZone = configHost.time.timeZone;

              microvm = {
                optimize.enable = false;
                mem = vm.ramMb;
                vcpu = vm.cores;
                hypervisor = "qemu";
                shares = [
                  {
                    tag = "waypipe-ssh-public-key";
                    source = configHost.ghaf.security.sshKeys.waypipeSshPublicKeyDir;
                    mountPoint = configHost.ghaf.security.sshKeys.waypipeSshPublicKeyDir;
                    proto = "virtiofs";
                  }
                  {
                    tag = "ro-store";
                    source = "/nix/store";
                    mountPoint = "/nix/.ro-store";
                    proto = "virtiofs";
                  }
                ];
                writableStoreOverlay = lib.mkIf config.ghaf.development.debug.tools.enable "/nix/.rw-store";

                qemu = {
                  extraArgs =
                    [
                      "-M"
                      "accel=kvm:tcg,mem-merge=on,sata=off"
                      "-device"
                      "vhost-vsock-pci,guest-cid=${toString cid}"
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
                    ];

                  machine =
                    {
                      # Use the same machine type as the host
                      x86_64-linux = "q35";
                      aarch64-linux = "virt";
                    }
                    .${configHost.nixpkgs.hostPlatform.system};
                };
              };
              fileSystems."${configHost.ghaf.security.sshKeys.waypipeSshPublicKeyDir}".options = [ "ro" ];

              imports = [ ../../../common ];
            }
          )
        ];
      };
    in
    {
      autostart = true;
      inherit (inputs) nixpkgs;
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
      type = types.listOf (
        types.submodule {
          options = {
            name = mkOption {
              description = ''
                Name of the AppVM
              '';
              type = types.str;
            };
            applications = mkOption {
              description = ''
                Applications to include in the AppVM
              '';
              type = types.listOf (
                types.submodule (
                  { config, lib, ... }:
                  {
                    options = rec {
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
            macAddress = mkOption {
              description = ''
                AppVM's network interface MAC address
              '';
              type = types.str;
            };
            ramMb = mkOption {
              description = ''
                Amount of RAM for this AppVM
              '';
              type = types.int;
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
            cid = mkOption {
              description = ''
                VSOCK context identifier (CID) for the AppVM
                Default value 0 means auto-assign using vsockBaseCID and AppVM index
              '';
              type = types.int;
              default = 0;
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
          };
        }
      );
      default = [ ];
    };

    extraModules = mkOption {
      description = ''
        List of additional modules to be imported and evaluated as part of
        appvm's NixOS configuration.
      '';
      default = [ ];
    };

    # Base VSOCK CID which is used for auto assigning CIDs for all AppVMs
    # For example, when it's set to 100, AppVMs will get 100, 101, 102, etc.
    # It is also possible to override the auto assinged CID using the vms.cid option
    vsockBaseCID = lib.mkOption {
      type = lib.types.int;
      default = 100;
      description = ''
        Context Identifier (CID) of the AppVM VSOCK
      '';
    };

    # Every AppVM has its own instance of Waypipe running in the GUIVM and
    # listening for incoming connections from the AppVM on its own port.
    # The port number each AppVM uses is waypipeBasePort + vmIndex.
    waypipeBasePort = lib.mkOption {
      type = lib.types.int;
      default = 1100;
      description = ''
        Waypipe base port number for AppVMs
      '';
    };
  };

  config =
    let
      makeSwtpmService =
        { vm }:
        let
          swtpmScript = pkgs.writeShellApplication {
            name = "${vm.name}-swtpm";
            runtimeInputs = with pkgs; [
              coreutils
              swtpm
            ];
            text = ''
              mkdir -p /var/lib/swtpm/${vm.name}-state
              swtpm socket --tpmstate dir=/var/lib/swtpm/${vm.name}-state \
                --ctrl type=unixio,path=/var/lib/swtpm/${vm.name}-sock \
                --tpm2 \
                --log level=20
            '';
          };
        in
        lib.mkIf vm.vtpm.enable {
          enable = true;
          description = "swtpm service for ${vm.name}";
          path = [ swtpmScript ];
          wantedBy = [ "microvms.target" ];
          serviceConfig = {
            Type = "simple";
            User = "microvm";
            Restart = "always";
            StateDirectory = "swtpm";
            StandardOutput = "journal";
            StandardError = "journal";
            ExecStart = "${swtpmScript}/bin/${vm.name}-swtpm";
          };
        };
      vmsWithWaypipe = lib.filter (
        vm: config.microvm.vms."${vm.name}-vm".config.config.ghaf.waypipe.enable
      ) cfg.vms;
    in
    lib.mkIf cfg.enable {
      # Define microvms for each AppVM configuration
      microvm.vms =
        let
          vms = lib.imap0 (vmIndex: vm: { "${vm.name}-vm" = makeVm { inherit vmIndex vm; }; }) cfg.vms;
        in
        lib.foldr lib.recursiveUpdate { } vms;

      # Apply host service dependencies, add swtpm
      systemd.services =
        let
          serviceDependencies = map (vm: {
            "microvm@${vm.name}-vm" = {
              # Host service dependencies
              after = optional config.ghaf.services.audio.enable "pulseaudio.service";
              requires = optional config.ghaf.services.audio.enable "pulseaudio.service";
              # Sleep appvms to give gui-vm time to start
              serviceConfig.ExecStartPre = "/bin/sh -c 'sleep 8'";
            };
            "${vm.name}-swtpm" = makeSwtpmService { inherit vm; };
          }) cfg.vms;
          # Each AppVM with waypipe needs its own instance of vsockproxy on the host
          proxyServices = map (vm: {
            "vsockproxy-${vm.name}" =
              config.microvm.vms."${vm.name}-vm".config.config.ghaf.waypipe.proxyService;
          }) vmsWithWaypipe;
        in
        lib.foldr lib.recursiveUpdate { } (serviceDependencies ++ proxyServices);

      # GUIVM needs to have a dedicated waypipe instance for each AppVM
      ghaf.virtualization.microvm.guivm.extraModules = [
        {
          systemd.user.services = lib.foldr lib.recursiveUpdate { } (
            map (vm: {
              "waypipe-${vm.name}" = config.microvm.vms."${vm.name}-vm".config.config.ghaf.waypipe.waypipeService;
            }) vmsWithWaypipe
          );
        }
      ];
    };
}
