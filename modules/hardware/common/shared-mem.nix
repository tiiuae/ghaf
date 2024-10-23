# Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# Module for Shared Memory Definitions
#
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.ghaf.shm;
  inherit (lib)
    foldl'
    lists
    mkMerge
    mkIf
    mkOption
    mdDoc
    types
    ;
in
{
  options.ghaf.shm = {
    enable = mkOption {
      type = types.bool;
      default = false;
      description = mdDoc ''
        Enables using shared memory between VMs and the host.
      '';
    };
    memSize = mkOption {
      type = types.int;
      default = 16;
      description = mdDoc ''
        Defines shared memory size in MBytes.
      '';
    };
    hugePageSz = mkOption {
      type = types.str;
      default = "2M";
      description = mdDoc ''
        Defines big memory area page size. Kernel supported values are
        2M and 1G.
      '';
      apply =
        value:
        if value != "2M" && value != "1G" then
          builtins.throw "Invalid huge memory area page size"
        else
          value;
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
    vms_enabled = mkOption {
      type = types.listOf types.str;
      default = [ ];
      description = mdDoc ''
        If set to a non-zero value, it maps the shared memory
        into this physical address. The value is arbitrary chosen, platform
        specific, in order not to conflict with other memory areas (e.g. PCI).
      '';
    };
    enable_host = mkOption {
      type = types.bool;
      default = false;
      description = mdDoc ''
        Enables memsocket on host.
      '';
    };
    instancesCount = mkOption {
      type = types.int;
      default =
        if cfg.enable_host then (builtins.length cfg.vms_enabled) + 1 else builtins.length cfg.vms_enabled;
      description = mdDoc ''
        Number of VMs entitled to use shared memory.
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
    display = mkOption {
      type = types.bool;
      default = false;
      description = "Display VMs using shared memory";
    };
  };
  config = mkIf cfg.enable (mkMerge [
    {
      boot.kernelParams =
        let
          hugepages = if cfg.hugePageSz == "2M" then cfg.memSize / 2 else cfg.memSize / 1024;
        in
        [
          "hugepagesz=${cfg.hugePageSz}"
          "hugepages=${toString hugepages}"
        ];
    }
    (mkIf cfg.enable_host {
      environment.systemPackages = [
        (pkgs.callPackage ../../../packages/memsocket { vms = cfg.instancesCount; })
      ];
    })
    {
      systemd.services.ivshmemsrv =
        let
          user = "microvm";
          group = "kvm";
          pidFilePath = "/tmp/ivshmem-server.pid";
          ivShMemSrv =
            let
              vectors = toString (2 * cfg.instancesCount);
            in
            pkgs.writeShellScriptBin "ivshmemsrv" ''
              chown ${user} /dev/hugepages
              chgrp ${group} /dev/hugepages
              if [ -S ${cfg.hostSocketPath} ]; then
                echo Erasing ${cfg.hostSocketPath} ${pidFilePath}
                rm -f ${cfg.hostSocketPath}
              fi
              ${pkgs.sudo}/sbin/sudo -u ${user} -g ${group} ${pkgs.qemu_kvm}/bin/ivshmem-server -p ${pidFilePath} -n ${vectors} -m /dev/hugepages/ -l ${(toString cfg.memSize) + "M"}
            '';
        in
        {
          enable = true;
          description = "Start qemu ivshmem memory server";
          path = [ ivShMemSrv ];
          wantedBy = [ "multi-user.target" ];
          serviceConfig = {
            Type = "oneshot";
            RemainAfterExit = true;
            StandardOutput = "journal";
            StandardError = "journal";
            ExecStart = "${ivShMemSrv}/bin/ivshmemsrv";
          };
        };
    }
    {
      microvm.vms =
        let
          memsocket = pkgs.callPackage ../../../packages/memsocket { vms = cfg.instancesCount; };
          vectors = toString (2 * cfg.instancesCount);
          makeAssignment = vmName: {
            ${vmName} = {
              config = {
                config = {
                  microvm = {
                    qemu = {
                      extraArgs = [
                        "-device"
                        "ivshmem-doorbell,vectors=${vectors},chardev=ivs_socket,flataddr=${cfg.flataddr}"
                        "-chardev"
                        "socket,path=${cfg.hostSocketPath},id=ivs_socket"
                      ];
                    };
                    kernelParams = [ "kvm_ivshmem.flataddr=${cfg.flataddr}" ];
                  };
                  boot.extraModulePackages = [
                    (pkgs.linuxPackages.callPackage ../../../packages/memsocket/module.nix {
                      inherit (config.microvm.vms.${vmName}.config.config.boot.kernelPackages) kernel;
                      vmCount = cfg.instancesCount;
                    })
                  ];
                  services = {
                    udev = {
                      extraRules = ''
                        SUBSYSTEM=="misc",KERNEL=="ivshmem",GROUP="kvm",MODE="0666"
                      '';
                    };
                  };
                  environment.systemPackages = [
                    memsocket
                  ];
                  systemd.user.services.memsocket =
                    if vmName == "gui-vm" then
                      {
                        enable = true;
                        description = "memsocket";
                        after = [ "labwc.service" ];
                        serviceConfig = {
                          Type = "simple";
                          ExecStart = "${memsocket}/bin/memsocket -c ${cfg.clientSocketPath}";
                          Restart = "always";
                          RestartSec = "1";
                        };
                        wantedBy = [ "ghaf-session.target" ];
                      }
                    else
                      # machines connecting to gui-vm
                      let
                        vmIndex = lists.findFirstIndex (vm: vm == vmName) null cfg.vms_enabled;
                      in
                      {
                        enable = true;
                        description = "memsocket";
                        serviceConfig = {
                          Type = "simple";
                          ExecStart = "${memsocket}/bin/memsocket -s ${cfg.serverSocketPath} ${builtins.toString vmIndex}";
                          Restart = "always";
                          RestartSec = "1";
                        };
                        wantedBy = [ "default.target" ];
                      };
                };
              };
            };
          };
        in
        foldl' lib.attrsets.recursiveUpdate { } (map makeAssignment cfg.vms_enabled);
    }
    {
      microvm.vms.gui-vm.config.config.boot.kernelParams = [
        "kvm_ivshmem.flataddr=${cfg.flataddr}"
      ];
    }
  ]);
}
