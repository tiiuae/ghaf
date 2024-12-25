# Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{ inputs }:
{
  config,
  lib,
  ...
}:
let
  vmName = "net-vm";
  macAddress = "02:00:00:01:01:01";

  netvmBaseConfiguration = {
    imports = [
      inputs.impermanence.nixosModules.impermanence
      inputs.self.nixosModules.givc-netvm
      (import ./common/vm-networking.nix {
        inherit
          config
          lib
          vmName
          macAddress
          ;
        internalIP = 1;
        isGateway = true;
      })

      ./common/storagevm.nix

      # To push logs to central location
      ../../../common/logging/client.nix
      (
        { lib, ... }:
        {
          imports = [ ../../../common ];

          ghaf = {
            # Profiles
            profiles.debug.enable = lib.mkDefault config.ghaf.profiles.debug.enable;
            development = {
              # NOTE: SSH port also becomes accessible on the network interface
              #       that has been passed through to NetVM
              ssh.daemon.enable = lib.mkDefault config.ghaf.development.ssh.daemon.enable;
              debug.tools.enable = lib.mkDefault config.ghaf.development.debug.tools.enable;
              nix-setup.enable = lib.mkDefault config.ghaf.development.nix-setup.enable;
            };
            users = {
              proxyUser = {
                enable = true;
                extraGroups = [
                  "networkmanager"
                ];
              };
            };

            # System
            systemd = {
              enable = true;
              withName = "netvm-systemd";
              withAudit = config.ghaf.profiles.debug.enable;
              withPolkit = true;
              withResolved = true;
              withTimesyncd = true;
              withDebug = config.ghaf.profiles.debug.enable;
              withHardenedConfigs = true;
            };
            givc.netvm.enable = true;

            # Storage
            storagevm = {
              enable = true;
              name = vmName;
              directories = [ "/etc/NetworkManager/system-connections/" ];
            };

            # Services
            # Logging client configuration
            logging.client.enable = config.ghaf.logging.client.enable;
            logging.client.endpoint = config.ghaf.logging.client.endpoint;

            # Provide BPF access to privileged users
            security.sysctl.network.bpf-access-level = lib.mkForce 1;
          };

          time.timeZone = config.time.timeZone;
          system.stateVersion = lib.trivial.release;

          nixpkgs = {
            buildPlatform.system = config.nixpkgs.buildPlatform.system;
            hostPlatform.system = config.nixpkgs.hostPlatform.system;
          };

          networking = {
            firewall.allowedTCPPorts = [ 53 ];
            firewall.allowedUDPPorts = [ 53 ];
          };

          # WORKAROUND: Create a rule to temporary hardcode device name for Wi-Fi adapter on x86
          # TODO this is a dirty hack to guard against adding this to Nvidia/vm targets which
          # dont have that definition structure yet defined. FIXME.
          # TODO the hardware.definition should not even be exposed in targets that do not consume it
          services.udev.extraRules = lib.mkIf (config.ghaf.hardware.definition.network.pciDevices != [ ]) ''
            SUBSYSTEM=="net", ACTION=="add", ATTRS{vendor}=="0x${(lib.head config.ghaf.hardware.definition.network.pciDevices).vendorId}", ATTRS{device}=="0x${(lib.head config.ghaf.hardware.definition.network.pciDevices).productId}", NAME="${(lib.head config.ghaf.hardware.definition.network.pciDevices).name}"
          '';

          microvm = {
            # Optimize is disabled because when it is enabled, qemu is built without libusb
            optimize.enable = false;
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
              machine =
                {
                  # Use the same machine type as the host
                  x86_64-linux = "q35";
                  aarch64-linux = "virt";
                }
                .${config.nixpkgs.hostPlatform.system};
              extraArgs = [
                "-device"
                "qemu-xhci"
              ];
            };
          };
        }
      )
    ];
  };
  cfg = config.ghaf.virtualization.microvm.netvm;
in
{
  options.ghaf.virtualization.microvm.netvm = {
    enable = lib.mkEnableOption "NetVM";

    extraModules = lib.mkOption {
      description = ''
        List of additional modules to be imported and evaluated as part of
        NetVM's NixOS configuration.
      '';
      default = [ ];
    };
  };

  config = lib.mkIf cfg.enable {
    microvm.vms."${vmName}" = {
      autostart = true;
      restartIfChanged = false;
      config = netvmBaseConfiguration // {
        imports = netvmBaseConfiguration.imports ++ cfg.extraModules;
      };
    };
  };
}
