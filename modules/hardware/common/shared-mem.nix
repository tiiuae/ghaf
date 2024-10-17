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
with lib;
{
  options.ghaf.shm = {
    enable = lib.mkOption {
      type = lib.types.bool;
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
    enable_host = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = mdDoc ''
        Enables memsocket on host.
      '';
      apply =
        enable:
        if enable && !config.ghaf.shm.enable then
          builtins.throw "Enable shared memory in order to use shm on host"
        else
          enable;
    };
    instancesCount = mkOption {
      type = types.int;
      default =
        if config.ghaf.shm.enable_host then
          (builtins.length config.ghaf.shm.vms_enabled) + 1
        else
          builtins.length config.ghaf.shm.vms_enabled;
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
      apply =
        enable:
        if enable && !config.ghaf.shm.enable then
          builtins.throw "Enable shared memory in order to use shm display"
        else
          enable;
    };
  };

  config.boot.kernelParams =
    let
      hugepagesz = "2M"; # valid values: "2M" and "1G", as kernel supports these huge pages' size
      hugepages =
        if hugepagesz == "2M" then config.ghaf.shm.memSize / 2 else config.ghaf.shm.memSize / 1024;
    in
    optionals config.ghaf.shm.enable [
      "hugepagesz=${hugepagesz}"
      "hugepages=${toString hugepages}"
    ];
  config.environment.systemPackages = optionals config.ghaf.shm.enable_host [
    (pkgs.callPackage ../../../packages/memsocket { vms = config.ghaf.shm.instancesCount; })
  ];

  config.systemd.services.ivshmemsrv =
    let
      pidFilePath = "/tmp/ivshmem-server.pid";
      ivShMemSrv =
        let
          vectors = toString (2 * config.ghaf.shm.instancesCount);
        in
        pkgs.writeShellScriptBin "ivshmemsrv" ''
          chown microvm /dev/hugepages
          chgrp kvm /dev/hugepages
          if [ -S ${config.ghaf.shm.hostSocketPath} ]; then
            echo Erasing ${config.ghaf.shm.hostSocketPath} ${pidFilePath}
            rm -f ${config.ghaf.shm.hostSocketPath}
          fi
          ${pkgs.sudo}/sbin/sudo -u microvm -g kvm ${pkgs.qemu_kvm}/bin/ivshmem-server -p ${pidFilePath} -n ${vectors} -m /dev/hugepages/ -l ${
            (toString config.ghaf.shm.memSize) + "M"
          }
        '';
    in
    lib.mkIf config.ghaf.shm.enable {
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
  config.microvm.vms =
    let
      memsocket = pkgs.callPackage ../../../packages/memsocket { vms = config.ghaf.shm.instancesCount; };
      vectors = toString (2 * config.ghaf.shm.instancesCount);
      makeAssignment = vmName: {
        ${vmName} = {
          config = {
            config = {
              microvm = {
                qemu = {
                  extraArgs = [
                    "-device"
                    "ivshmem-doorbell,vectors=${vectors},chardev=ivs_socket,flataddr=${config.ghaf.shm.flataddr}"
                    "-chardev"
                    "socket,path=${config.ghaf.shm.hostSocketPath},id=ivs_socket"
                  ];
                };
                kernelParams = [ "kvm_ivshmem.flataddr=${config.ghaf.shm.flataddr}" ];
              };
              boot.extraModulePackages = [
                (pkgs.linuxPackages.callPackage ../../../packages/memsocket/module.nix {
                  inherit (config.microvm.vms.${vmName}.config.config.boot.kernelPackages) kernel;
                  vmCount = config.ghaf.shm.instancesCount;
                })
              ];
              services = {
                udev = {
                  extraRules = ''
                    SUBSYSTEM=="misc",KERNEL=="ivshmem",GROUP="kvm",MODE="0666"
                  '';
                };
              };
              environment.systemPackages = optionals config.ghaf.shm.enable [
                memsocket
              ];
              systemd.user.services.memsocket =
                if vmName == "gui-vm" then
                  lib.mkIf config.ghaf.shm.enable {
                    enable = true;
                    description = "memsocket";
                    after = [ "labwc.service" ];
                    serviceConfig = {
                      Type = "simple";
                      ExecStart = "${memsocket}/bin/memsocket -c ${config.ghaf.shm.clientSocketPath}";
                      Restart = "always";
                      RestartSec = "1";
                    };
                    wantedBy = [ "ghaf-session.target" ];
                  }
                else
                  # machines connecting to gui-vm
                  let
                    vmIndex = lib.lists.findFirstIndex (vm: vm == vmName) null config.ghaf.shm.vms_enabled;
                  in
                  lib.mkIf config.ghaf.shm.enable {
                    enable = true;
                    description = "memsocket";
                    serviceConfig = {
                      Type = "simple";
                      ExecStart = "${memsocket}/bin/memsocket -s ${config.ghaf.shm.serverSocketPath} ${builtins.toString vmIndex}";
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
    mkIf config.ghaf.shm.enable (
      foldl' lib.attrsets.recursiveUpdate { } (map makeAssignment config.ghaf.shm.vms_enabled)
    );

  config.ghaf.hardware.definition.gpu.kernelConfig.kernelParams = optionals config.ghaf.shm.enable [
    "kvm_ivshmem.flataddr=${config.ghaf.shm.flataddr}"
  ];
}
