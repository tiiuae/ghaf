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
        Enables shared memory communication between virtual machines (VMs) and the host
      '';
    };
    memSize = mkOption {
      type = types.int;
      default = 16;
      description = mdDoc ''
        Specifies the size of the shared memory region, measured in 
        megabytes (MB)
      '';
    };
    hugePageSz = mkOption {
      type = types.str;
      default = "2M";
      description = mdDoc ''
        Specifies the size of the large memory page area. Supported kernel 
        values are 2 MB and 1 GB
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
        Specifies the path to the shared memory socket, used by QEMU 
        instances for inter-VM memory sharing and interrupt signaling
      '';
    };
    flataddr = mkOption {
      type = types.str;
      default = "0x920000000";
      description = mdDoc ''
        Maps the shared memory to a physical address if set to a non-zero value.
        The address must be platform-specific and arbitrarily chosen to avoid 
        conflicts with other memory areas, such as PCI regions.
      '';
    };
    vms_enabled = mkOption {
      type = types.listOf types.str;
      default = [ ];
      description = mdDoc ''
        List of vms having access to shared memory
      '';
    };
    enable_host = mkOption {
      type = types.bool;
      default = false;
      description = mdDoc ''
        Enables the memsocket functionality on the host system
      '';
    };
    shmSlots = mkOption {
      type = types.int;
      default =
        if cfg.enable_host then (builtins.length cfg.vms_enabled) + 1 else builtins.length cfg.vms_enabled;
      description = mdDoc ''
        Number of memory slots allocated in the shared memory region
      '';
    };
    clientSocketPath = mkOption {
      type = types.path;
      default = "/run/user/${builtins.toString config.ghaf.users.accounts.uid}/memsocket-client.sock";
      description = mdDoc ''
        Specifies the path of the listening socket, which is used by Waypipe 
        or other server applications as the output socket in its server mode for 
        data transmission
      '';
    };
    serverSocketPath = mkOption {
      type = types.path;
      default = "/run/user/${builtins.toString config.ghaf.users.accounts.uid}/memsocket-server.sock";
      description = mdDoc ''
        Specifies the location of the output socket, which will connected to 
        in order to receive data from AppVMs. This socket must be created by 
        another application, such as Waypipe, when operating in client mode
      '';
    };
    display = mkOption {
      type = types.bool;
      default = false;
      description = mdDoc ''
        Enables the use of shared memory with Waypipe for Wayland-enabled 
        applications running on virtual machines (VMs), facilitating 
        efficient inter-VM communication
      '';
    };
  };
  config =
    let
      user = "microvm";
      group = "kvm";
    in
    mkIf cfg.enable (mkMerge [
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
      {
        systemd.tmpfiles.rules = [
          "d /dev/hugepages 0755 ${user} ${group} - -"
        ];
      }
      (mkIf cfg.enable_host {
        environment.systemPackages = [
          (pkgs.callPackage ../../../packages/memsocket { inherit (cfg) shmSlots; })
        ];
      })
      {
        systemd.services.ivshmemsrv =
          let
            pidFilePath = "/tmp/ivshmem-server.pid";
            ivShMemSrv =
              let
                vectors = toString (2 * cfg.shmSlots);
              in
              pkgs.writeShellScriptBin "ivshmemsrv" ''
                if [ -S ${cfg.hostSocketPath} ]; then
                  echo Erasing ${cfg.hostSocketPath} ${pidFilePath}
                  rm -f ${cfg.hostSocketPath}
                fi
                ${pkgs.qemu_kvm}/bin/ivshmem-server -p ${pidFilePath} -n ${vectors} -m /dev/hugepages/ -l ${(toString cfg.memSize) + "M"}
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
              User = user;
              Group = group;
            };
          };
      }
      {
        microvm.vms =
          let
            memsocket = pkgs.callPackage ../../../packages/memsocket { inherit (cfg) shmSlots; };
            vectors = toString (2 * cfg.shmSlots);
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
                        inherit (cfg) shmSlots;
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
                            # option '-l -1': listen to all slots. If you want to run other servers
                            # for some slots, provide a list of handled slots, e.g.: '-l 1,3,5'
                            ExecStart = "${memsocket}/bin/memsocket -s ${cfg.serverSocketPath} -l -1";
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
                            ExecStart = "${memsocket}/bin/memsocket -c ${cfg.clientSocketPath} ${builtins.toString vmIndex}";
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
