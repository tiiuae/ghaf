# Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
{
  config,
  lib,
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
        memSize = mkOption {
          type = lib.types.str;
          default = "16M";
          description = mdDoc ''
          Defines shared memory size
        '';
        };
        vmCount = mkOption {
          type = lib.types.int;
          default = 6;
          description = mdDoc ''
          Defines maximum number of application VMs
        '';
        };
        serverSocketPath = mkOption {
          type = lib.types.str;
          default = "/tmp/memsocket-server.sock";
          description = mdDoc ''
          Defines location of the listening socket.
          It's used by waypipe as an output socket when running in server mode
        '';
        };
        clientSocketPath = mkOption {
          type = lib.types.str;
          default = "/tmp/memsocket-client.sock";
          description = mdDoc ''
          Defines location of the output socket. It's outputed
          with data coming from AppVMs.
          It's used by waypipe as an input socket when running in client mode
        '';
        };
          hostSocketPath = mkOption {
          type = lib.types.str;
          default = "/tmp/ivshmem_socket";
          description = mdDoc ''
          Defines location of the shared memory socket. It's used by qemu 
          instances for memory sharing and sending interrupts.
        '';
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
