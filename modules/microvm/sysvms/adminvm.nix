# Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{ inputs }:
{
  config,
  lib,
  ...
}:
let

  configHost = config;
  vmName = "admin-vm";

  adminvmBaseConfiguration = {
    imports = [
      inputs.preservation.nixosModules.preservation
      inputs.self.nixosModules.givc
      inputs.self.nixosModules.vm-modules
      inputs.self.nixosModules.profiles
      (
        { lib, pkgs, ... }:
        let
          cfg = config.ghaf.virtualization.microvm.appvm;
          vms = lib.filterAttrs (_: vm: vm.enable && vm.vtpm.enable) cfg.vms;

          makeSwtpmService =
            name: basePort:
            let
              swtpmScript = pkgs.writeShellApplication {
                name = "${name}-swtpm-bin";
                runtimeInputs = with pkgs; [
                  coreutils
                  swtpm
                ];
                text = ''
                  mkdir -p /var/lib/swtpm/${name}/state
                  swtpm socket --tpmstate dir=/var/lib/swtpm/${name}/state \
                    --ctrl type=tcp,port=${toString basePort} \
                    --server type=tcp,port=${toString (basePort + 1)} \
                    --tpm2 \
                    --log level=20
                '';
              };
            in
            {
              description = "swtpm service for ${name}";
              path = [ swtpmScript ];
              wantedBy = [ "multi-user.target" ];
              serviceConfig = {
                Type = "exec";
                Restart = "always";
                User = "swtpm_${name}";
                StateDirectory = "swtpm/${name}";
                StateDirectoryMode = "0700";
                StandardOutput = "journal";
                StandardError = "journal";
                ExecStart = lib.getExe swtpmScript;
              };
            };

          makeSocatService =
            name: channel: port:
            let
              socatScript = pkgs.writeShellApplication {
                name = "${name}-socat";
                runtimeInputs = with pkgs; [
                  socat
                ];
                text = ''
                  socat VSOCK-LISTEN:${toString port},fork TCP:127.0.0.1:${toString port}
                '';
              };
            in
            {
              description = "socat ${channel} channel for ${name}";
              path = [ socatScript ];
              wantedBy = [ "multi-user.target" ];
              serviceConfig = {
                Type = "simple";
                Restart = "always";
                DynamicUser = "on";
                StandardOutput = "journal";
                StandardError = "journal";
                ExecStart = lib.getExe socatScript;
              };
            };

          makeSwtpmInstanceConfig = name: vm: {
            users.users."swtpm_${name}" = {
              isSystemUser = true;
              home = "/var/lib/swtpm/${name}";
              group = "swtpm_${name}";
            };
            users.groups."swtpm_${name}" = { };

            systemd.services = {
              "${name}-swtpm" = makeSwtpmService name vm.vtpm.basePort;
              "${name}-socat-control" = makeSocatService name "control" vm.vtpm.basePort;
              "${name}-socat-data" = makeSocatService name "data" (vm.vtpm.basePort + 1);
            };
          };

          configs = lib.mapAttrsToList makeSwtpmInstanceConfig vms;
        in
        lib.foldr lib.recursiveUpdate { } configs
      )
      (
        { lib, ... }:
        {
          ghaf = {
            # Profiles
            profiles.debug.enable = lib.mkDefault configHost.ghaf.profiles.debug.enable;
            development = {
              # NOTE: SSH port also becomes accessible on the network interface
              #       that has been passed through to VM
              ssh.daemon.enable = lib.mkDefault configHost.ghaf.development.ssh.daemon.enable;
              debug.tools.enable = lib.mkDefault configHost.ghaf.development.debug.tools.enable;
              nix-setup.enable = lib.mkDefault configHost.ghaf.development.nix-setup.enable;
            };

            # System
            type = "admin-vm";
            systemd = {
              enable = true;
              withName = "adminvm-systemd";
              withNss = true;
              withResolved = true;
              withPolkit = true;
              withTimesyncd = true;
              withDebug = configHost.ghaf.profiles.debug.enable;
              withHardenedConfigs = true;
            };
            givc.adminvm.enable = true;

            # Storage
            storagevm = {
              enable = true;
              name = vmName;
              files = [
                "/etc/locale-givc.conf"
                "/etc/timezone.conf"
              ];
              directories = [
                "/var/lib/swtpm"
              ];
            };
            # Networking
            virtualization.microvm.vm-networking = {
              enable = true;
              inherit vmName;
            };

            virtualization.microvm.tpm-passthrough = {
              enable = true;
              rootNVIndex = "0x81100100";
            };

            # Services
            logging = {
              server = {
                inherit (configHost.ghaf.logging) enable;
              };
            };
          };

          system.stateVersion = lib.trivial.release;

          nixpkgs = {
            buildPlatform.system = configHost.nixpkgs.buildPlatform.system;
            hostPlatform.system = configHost.nixpkgs.hostPlatform.system;
          };

          microvm = {
            optimize.enable = false;
            #TODO: Add back support cloud-hypervisor
            #the system fails to switch root to the stage2 with cloud-hypervisor
            hypervisor = "qemu";
            qemu = {
              extraArgs = [
                "-device"
                "vhost-vsock-pci,guest-cid=${toString config.ghaf.networking.hosts.${vmName}.cid}"
              ];
            };
            shares = [
              {
                tag = "ro-store";
                source = "/nix/store";
                mountPoint = "/nix/.ro-store";
                proto = "virtiofs";
              }
              {
                tag = "ghaf-common";
                source = "/persist/common";
                mountPoint = "/etc/common";
                proto = "virtiofs";
              }
            ];

            writableStoreOverlay = lib.mkIf config.ghaf.development.debug.tools.enable "/nix/.rw-store";
          };
        }
      )
    ];
  };
  cfg = config.ghaf.virtualization.microvm.adminvm;
in
{
  options.ghaf.virtualization.microvm.adminvm = {
    enable = lib.mkEnableOption "AdminVM";

    extraModules = lib.mkOption {
      description = ''
        List of additional modules to be imported and evaluated as part of
        AdminVM's NixOS configuration.
      '';
      default = [ ];
    };
    extraNetworking = lib.mkOption {
      type = lib.types.networking;
      description = "Extra Networking option";
      default = { };
    };
  };

  config = lib.mkIf cfg.enable {
    ghaf.common.extraNetworking.hosts.${vmName} = cfg.extraNetworking;

    microvm.vms."${vmName}" = {
      autostart = true;
      inherit (inputs) nixpkgs;
      specialArgs = { inherit lib; };
      config = adminvmBaseConfiguration // {
        imports = adminvmBaseConfiguration.imports ++ cfg.extraModules;
      };
    };
  };
}
