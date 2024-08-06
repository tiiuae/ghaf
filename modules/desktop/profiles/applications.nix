# Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.ghaf.profiles.applications;
in
  with lib; {
    options.ghaf.profiles.applications = {
      enable = mkEnableOption "Some sample applications";
      #TODO Create options to allow enabling individual apps
      #weston.ini.nix mods needed
      ivShMemServer = {
        enable = mkOption {
          type = types.bool;
          default = false;
          description = "Enable memory sharing between virtual machines";
        };
        memSize = mkOption {
          type = types.int;
          default = 16;
          description = mdDoc ''
            Defines shared memory size in MBytes
          '';
        };
        serverSocketPath = mkOption {
          type = types.path;
          default = "/run/user/${builtins.toString config.ghaf.users.accounts.uid}/memsocket-server.sock";
          description = mdDoc ''
            Defines location of the listening socket.
            It's used by waypipe as an output socket when running in server mode
          '';
        };
        clientSocketPath = mkOption {
          type = types.path;
          default = "/run/user/${builtins.toString config.ghaf.users.accounts.uid}/memsocket-client.sock";
          description = mdDoc ''
            Defines location of the output socket. It's fed
            with data coming from AppVMs.
            It's used by waypipe as an input socket when running in client mode
          '';
        };
        hostSocketPath = mkOption {
          type = types.path;
          default = "/tmp/ivshmem_socket"; # The value is hardcoded in the application
          description = mdDoc ''
            Defines location of the shared memory socket. It's used by qemu
            instances for memory sharing and sending interrupts.
          '';
        };
        flataddr = mkOption {
          type = types.str;
          default = "0x920000000";
          description = mdDoc ''
            If set to a non-zero value, it maps the shared memory
            into this physical address. The value is arbitrary chosen, platform
            specific, in order not to conflict with other memory areas (e.g. PCI).
          '';
        };
        qemuOption = mkOption {
          type = types.listOf types.str;
          default = let
            vectors = toString (2 * (builtins.length config.ghaf.reference.appvms.enabled-app-vms));
          in [
            "-device"
            "ivshmem-doorbell,vectors=${vectors},chardev=ivs_socket,flataddr=${config.ghaf.profiles.applications.ivShMemServer.flataddr}"
            "-chardev"
            "socket,path=${config.ghaf.profiles.applications.ivShMemServer.hostSocketPath},id=ivs_socket"
          ];
        };
        display = mkOption {
          type = types.bool;
          default = false;
          description = "Display VMs using shared memory";
        };
        kernelPatches = mkOption {
          type = types.listOf types.attrs;
          default =
            if config.ghaf.profiles.applications.ivShMemServer.enable
            then [
              {
                name = "Shared memory PCI driver";
                patch = pkgs.fetchpatch {
                  url = "https://raw.githubusercontent.com/tiiuae/shmsockproxy/main/0001-ivshmem-driver.patch";
                  sha256 = "sha256-Nj9U9QRqgMluuF9ui946mqG6RQGxNyDmfcYHqMZlcvc=";
                };
                extraConfig = ''
                  KVM_IVSHMEM_VM_COUNT ${toString (builtins.length config.ghaf.reference.appvms.enabled-app-vms)}
                '';
              }
            ]
            else [];
        };
      };
    };

    config = mkIf cfg.enable {
      # TODO: Needs more generic support for defining application launchers
      #       across different window managers.
      ghaf = {
        profiles.graphics.enable = true;
        graphics.enableDemoApplications = true;
      };
    };
  }
