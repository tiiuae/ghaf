# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
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
    lists
    mkMerge
    mkIf
    mkOption
    types
    ;
in
{
  options.ghaf.shm = {
    enable = mkOption {
      type = types.bool;
      default = false;
      description = ''
        Enables shared memory communication between virtual machines (VMs)
      '';
    };
    memSize = mkOption {
      type = types.int;
      default = 16;
      description = ''
        Specifies the size of the shared memory region, measured in
        megabytes (MB)
      '';
    };
    hugePageSz = mkOption {
      type = types.str;
      default = "2M";
      description = ''
        Specifies the size of the large memory page area. Supported kernel
        values are 2 MB and 1 GB
      '';
      apply =
        value: if value != "2M" && value != "1G" then throw "Invalid huge memory area page size" else value;
    };
    hostSocketPath = mkOption {
      type = types.path;
      default = "/tmp/ivshmem_socket"; # The value is hardcoded in the application
      description = ''
        Specifies the path to the shared memory socket, used by QEMU
        instances for inter-VM memory sharing and interrupt signaling
      '';
    };
    flataddr = mkOption {
      type = types.str;
      default = "0x920000000";
      description = ''
        Maps the shared memory to a physical address if set to a non-zero value.
        The address must be platform-specific and arbitrarily chosen to avoid
        conflicts with other memory areas, such as PCI regions.
      '';
    };
    vms_enabled = mkOption {
      type = types.listOf types.str;
      default = [ ];
      description = ''
        List of vms having access to shared memory
      '';
    };
    enable_host = mkOption {
      type = types.bool;
      default = false;
      description = ''
        Enables the memsocket functionality on the host system
      '';
    };
    instancesCount = mkOption {
      type = types.int;
      default =
        if cfg.enable_host then (builtins.length cfg.vms_enabled) + 1 else builtins.length cfg.vms_enabled;
      description = ''
        Number of memory slots allocated in the shared memory region
      '';
    };
    serverSocketPath = mkOption {
      type = types.path;
      default = "/run/user/${toString config.ghaf.users.homedUser.uid}/memsocket-server.sock";
      description = ''
        Specifies the path of the listening socket, which is used by Waypipe
        or other server applications as the output socket in server mode for
        data transmission
      '';
    };
    clientSocketPath = mkOption {
      type = types.path;
      default = "/run/user/${toString config.ghaf.users.homedUser.uid}/memsocket-client.sock";
      description = ''
        Specifies the location of the output socket, which will connected to
        in order to receive data from AppVMs. This socket must be created by
        another application, such as Waypipe, when operating in client mode
      '';
    };
    display = mkOption {
      type = types.bool;
      default = false;
      description = ''
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
          (pkgs.memsocket.override { vms = cfg.instancesCount; })
        ];
      })
      {
        systemd.services.ivshmemsrv =
          let
            pidFilePath = "/tmp/ivshmem-server.pid";
            ivShMemSrv =
              let
                vectors = toString (2 * cfg.instancesCount);
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
            memsocket = pkgs.memsocket.override { vms = cfg.instancesCount; };
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
                    boot.extraModulePackages =
                      let
                        vmConfig = lib.ghaf.getVmConfig config.microvm.vms.${vmName};
                      in
                      [
                        # TODO: fix this to not call back to packages dir
                        (pkgs.linuxPackages.callPackage ../../../packages/pkgs-by-name/memsocket/module.nix {
                          inherit (vmConfig.boot.kernelPackages) kernel;
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
                          serviceConfig = {
                            Type = "simple";
                            ExecStart = "${memsocket}/bin/memsocket -c ${cfg.clientSocketPath}";
                            Restart = "always";
                            RestartSec = "1";
                          };
                          after = [ "ghaf-session.target" ];
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
                            ExecStart = "${memsocket}/bin/memsocket -s ${cfg.serverSocketPath} ${toString vmIndex}";
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
          lib.foldl' lib.attrsets.recursiveUpdate { } (map makeAssignment cfg.vms_enabled);
      }
      {
        # When using evaluatedConfig, we can't set config directly.
        # Instead, add kernel params via extraModules which profile collects.
        ghaf.virtualization.microvm.guivm.extraModules = [
          {
            boot.kernelParams = [
              "kvm_ivshmem.flataddr=${cfg.flataddr}"
            ];
          }
        ];
      }
    ]);
}
