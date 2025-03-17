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
    mkMerge
    mkIf
    mkOption
    types
    ;
  # Get the list of enabled only services
  enabledServices = lib.filterAttrs (_name: serverAttrs: serverAttrs.enabled) cfg.service;

  # Get the list of enabled services that run on VMs (i.e. excluding host services)
  enabledVmServices =
    isVM:
    lib.filterAttrs (_name: serverAttrs: serverAttrs.serverConfig.runsOnVm == isVM) enabledServices;

  # Get the list of clients for a given service
  # Sample output: (clientsPerService "gui-vm") -> ["chrome-vm" "business-vm" "comms-vm"]
  clientsPerService =
    service:
    lib.flatten (
      lib.mapAttrsToList (
        name: value: if (name == service || service == "all") then value.clients else [ ]
      ) enabledServices
    );

  # Get the list of all VMs (clients and servers)
  # Sample output: ["chrome-vm" "business-vm" "comms-vm"]
  allVMs = lib.unique (
    lib.concatLists (
      map (s: (lib.filter (client: client != "host") s.clients) ++ [ s.server ]) (
        builtins.attrValues enabledServices
      )
    )
  );

  # Get the list of client-service pairs
  # Sample output:
  # [ {client = "chrome-vm"; service = "audio";} {client = "business-vm"; service = "audio";} ]
  clientServicePairs = lib.unique (
    lib.concatLists (
      map (
        s:
        map (c: {
          service = s.name;
          client = c;
        }) s.clients
      ) (lib.mapAttrsToList (name: attrs: attrs // { inherit name; }) enabledServices)
    )
  );

  # Get the list of client-service pairs with their assigned IDs
  # Sample output:
  # [ {client = "chrome-vm";   id = 0; service = "audio";}
  #   {client = "business-vm"; id = 1; service = "audio";}]
  clientServiceWithID = lib.foldl' (
    acc: pair: acc ++ [ (pair // { id = builtins.length acc; }) ]
  ) [ ] clientServicePairs;

  # Get the client slot ID (integer) for a given client and service
  clientID =
    client: service:
    let
      filtered = builtins.filter (x: x.client == client && x.service == service) clientServiceWithID;
    in
    if filtered != [ ] then (builtins.toString (builtins.head filtered).id) else null;

  # Generate a string of comma-separated client IDs for a given service, to be used in command line
  # arguments for the memsocket server
  # Sample output:  { audio = "0,1,2"; gui = "3,4,5,6,7"; }
  clientsArg = lib.foldl' (
    acc: pair:
    (
      acc
      // {
        "${pair.service}" =
          if (builtins.hasAttr "${pair.service}" acc) then
            acc.${pair.service} + "," + (builtins.toString pair.id)
          else
            (builtins.toString pair.id);
      }
    )
  ) { } clientServiceWithID;
in
{
  options.ghaf.shm = {
    enable = mkOption {
      type = types.bool;
      default = false;
      description = ''
        Enables shared memory communication between virtual machines (VMs) and the host
      '';
    };
    gui = mkOption {
      type = types.bool;
      default = false;
      description = ''
        Enables shared memory for transferring GUI data between virtual machines
      '';
    };
    audio = mkOption {
      type = types.bool;
      default = true;
      description = ''
        Enables shared memory for transferring audio data between virtual machines
      '';
      apply = value: if value then cfg.enable else false;
    };
    memSize = mkOption {
      type = types.int;
      default = 32;
      description = ''
        Specifies the size of the shared memory region, measured in
        megabytes (MB)
      '';
    };

    service = mkOption {
      type = types.attrsOf types.anything;
      default =
        let
          stdConfig = service: {
            server = "${service}-vm";
            clientSocketPath = "/run/memsocket/${service}-client.sock";
            serverSocketPath = service: suffix: "/run/memsocket/${service}${suffix}.sock";
            userService = false;
            serverConfig = {
              runsOnVm = true;
            };
          };
        in
        {
          gui =
            let
              enabled = cfg.enable && cfg.gui;
            in
            mkIf cfg.enable (
              lib.attrsets.recursiveUpdate (stdConfig "gui") {
                inherit enabled;
                serverSocketPath = service: suffix: "/tmp/${service}${suffix}.sock";
                serverConfig = {
                  userService = true;
                  systemdParams = service: suffix: {
                    wantedBy = [ "ghaf-session.target" ];
                    after = [ "waypipe${suffix}.service" ];
                    partOf = [ "waypipe${suffix}.service" ];
                    bindsTo = [ "waypipe${suffix}.service" ];
                    serviceConfig = {
                      KillSignal = "SIGTERM";
                      ExecStop = "${pkgs.coreutils}/bin/rm -f ${cfg.service.gui.serverSocketPath service suffix}";
                    };
                  };
                  multiProcess = true;
                };
                clients = config.ghaf.virtualization.microvm.appvm.shm-gui-enabled-vms;
                clientConfig = {
                  userService = false;
                  systemdParams = {
                    wantedBy = [ "default.target" ];
                    serviceConfig = {
                      KillSignal = "SIGTERM";
                      User = "appuser";
                      Group = "users";
                    };
                  };
                };
              }
            );
        };
      description = ''
        Specifies the configuration of shared memory services:
        server and client VMs. The server VMs are named after the 
        service name.
      '';
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
    shmSlots = mkOption {
      type = types.int;
      default = builtins.length clientServiceWithID;
      description = ''
        Number of memory slots allocated in the shared memory region
      '';
    };
  };
  config =
    let
      user = "microvm";
      group = "kvm";
      memsocket = pkgs.memsocket-app.override {
        inherit (cfg) shmSlots;
        debug = false;
      };
      vectors = toString (2 * cfg.shmSlots);
      defaultClientConfig =
        data:
        lib.attrsets.recursiveUpdate {
          enable = true;
          description = "memsocket";
          serviceConfig = {
            Type = "simple";
            ExecStart =
              let
                hostOpt = if data.client == "host" then "-h ${cfg.hostSocketPath}" else "";
              in
              "${memsocket}/bin/memsocket ${hostOpt} -c ${
                cfg.service.${data.service}.clientSocketPath
              } ${builtins.toString (clientID data.client data.service)}";
            Restart = "always";
            RestartSec = "1";
            RuntimeDirectory = "memsocket";
            RuntimeDirectoryMode = "0770";
          };
        } cfg.service.${data.service}.clientConfig.systemdParams;
      clientConfigTemplate =
        data:
        let
          base =
            if cfg.service.${data.service}.clientConfig.userService then
              {
                user.services."memsocket-${data.service}-client" = defaultClientConfig data;
              }
            else
              {
                services."memsocket-${data.service}-client" = defaultClientConfig data;
              };

        in
        if data.client == "host" then
          base
        else
          {
            "${data.client}".config.config.systemd = base;
          };

      defaultServerConfig =
        clientSuffix: clientId: service: runsOnVm:
        lib.attrsets.recursiveUpdate {
          enable = true;
          description = "memsocket";
          serviceConfig = {
            Type = "simple";
            ExecStart =
              let
                hostOpt = if !runsOnVm then "-h ${cfg.hostSocketPath}" else "";
              in
              "${memsocket}/bin/memsocket -s ${
                cfg.service.${service}.serverSocketPath service clientSuffix
              } ${hostOpt} -l ${clientId}";
            Restart = "always";
            RestartSec = "1";
            RuntimeDirectory = "memsocket";
            RuntimeDirectoryMode = "0750";
          };
        } (cfg.service.${service}.serverConfig.systemdParams service clientSuffix);
      serverConfigTemplate =
        clientSuffix: clientId: service:
        let
          base =
            if cfg.service.${service}.serverConfig.userService then
              {
                user.services."memsocket-${service}${clientSuffix}-service" =
                  defaultServerConfig clientSuffix clientId service
                    cfg.service.${service}.serverConfig.runsOnVm;
              }
            else
              {
                services."memsocket-${service}${clientSuffix}-service" =
                  defaultServerConfig clientSuffix clientId service
                    cfg.service.${service}.serverConfig.runsOnVm;
              };
        in
        if cfg.service.${service}.serverConfig.runsOnVm then
          {
            "${cfg.service.${service}.server}".config.config.systemd = base;
          }
        else
          base;
      serverConfig =
        service:
        let
          multiProcess =
            if lib.attrsets.hasAttr "multiProcess" cfg.service.${service}.serverConfig then
              cfg.service.${service}.serverConfig.multiProcess
            else
              false;
        in
        if multiProcess then
          (lib.foldl' lib.attrsets.recursiveUpdate { } (
            map (client: serverConfigTemplate "-${client}" (clientID client service) service) (
              clientsPerService service
            )
          ))
        else
          (serverConfigTemplate "" # clientSuffix
            clientsArg.${service}
            service
          );

    in
    mkIf cfg.enable (mkMerge [
      {
        systemd.services.setShmOwnership = {
          description = "Set ownership for /dev/ivshmem";
          wantedBy = [ "sysinit.target" ];
          before = [ "ivshmemsrv.service" ];
          serviceConfig = {
            Type = "oneshot";
            ExecStart = [
              "/run/current-system/sw/bin/chown ${user}:${group} /dev/ivshmem"
              "/run/current-system/sw/bin/chmod 0660 /dev/ivshmem"
            ];
            RemainAfterExit = true;
          };
        };
      }
      (mkIf cfg.enable {
        environment.systemPackages = [
          memsocket
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
                ${pkgs.qemu_kvm}/bin/ivshmem-server -p ${pidFilePath} -n ${vectors} -m /dev -l ${(toString cfg.memSize) + "M"}
              '';
          in
          {
            enable = true;
            description = "qemu ivshmem memory server";
            path = [ ivShMemSrv ];
            wantedBy = [ "sysinit.target" ];
            requires = [ "setShmOwnership.service" ];
            serviceConfig = {
              Type = "simple";
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
        boot.extraModulePackages = [
          (pkgs.memsocket-secmem.override {
            inherit (config.boot.kernelPackages) kernel;
            inherit (cfg) shmSlots;
            memSize = cfg.memSize * 1024 * 1024;
            inherit clientServiceWithID;
          })
        ];
      }
      # shared memory driver for the host with slots control
      {
        boot.kernelModules = [ "secshm" ];
      }
      # add host systemd client services
      {
        systemd = foldl' lib.attrsets.recursiveUpdate { } (
          map clientConfigTemplate (lib.filter (data: data.client == "host") clientServicePairs)
        );
      }
      # add host systemd server services
      {
        systemd = lib.foldl' lib.attrsets.recursiveUpdate { } (
          map serverConfig (builtins.attrNames (enabledVmServices false))
        );
      }
      {
        microvm.vms =
          let
            configCommon = vmName: {
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
                      (pkgs.memsocket-module.override {
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
                  };
                };
              };
            };
            # generate config for memsocket services  running in client mode on VMs
            clientsConfig = foldl' lib.attrsets.recursiveUpdate { } (
              map clientConfigTemplate (lib.filter (data: data.client != "host") clientServicePairs)
            );
            # generate config for memsocket services running in server mode on VMs
            clientsAndServers = lib.foldl' lib.attrsets.recursiveUpdate clientsConfig (
              map serverConfig (builtins.attrNames (enabledVmServices true))
            );
            finalMicroVmsConfig = foldl' lib.attrsets.recursiveUpdate clientsAndServers (
              map configCommon allVMs
            );
          in
          finalMicroVmsConfig;
      }
    ]);
}
