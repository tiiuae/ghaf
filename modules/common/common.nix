# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# TODO: Refactor even more.
#       This is the old "host/default.nix" file.
#
# ghaf.common: Interface to share ghaf configs from host to VMs
#
{
  config,
  pkgs,
  lib,
  ...
}:
let
  inherit (lib)
    mkOption
    types
    optionalAttrs
    hasAttrByPath
    ;
in
{
  _file = ./common.nix;

  imports = [
    # TODO remove this when the minimal config is defined
    # Replace with the baseModules definition
    # UPDATE 26.07.2023:
    # This line breaks build of GUIVM. No investigations of a
    # root cause are done so far.
    #(modulesPath + "/profiles/minimal.nix")
  ];

  options.ghaf = {
    common = {
      policies = mkOption {
        description = "System policies";
        default = { };
        # <vm-name>.<policy-name> = {}
        type = types.attrsOf (types.attrsOf lib.types.policy);
      };
      vms = mkOption {
        type = types.listOf types.str;
        default = [ ];
        description = "List of VMs currently enabled.";
      };
      adminHost = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = "List of admin hosts currently enabled.";
      };
      systemHosts = mkOption {
        type = types.listOf types.str;
        default = [ ];
        description = "List of system hosts currently enabled.";
      };
      appHosts = mkOption {
        type = types.listOf types.str;
        default = [ ];
        description = "List of app hosts currently enabled.";
      };
      extraNetworking = {
        hosts = mkOption {
          type = types.attrsOf lib.types.networking;
          description = "Extra host entries that override or extend the generated ones.";
          default = { };
        };
        enableStaticArp = mkOption {
          type = types.bool;
          default = true;
          description = ''
            Enable static ARP entries for all hosts, and prevent any ARP traffic being sent or received
            on the internal network. This is useful to prevent ARP spoofing attacks between VMs.
          '';
        };
      };
      hardware = {
        nics = mkOption {
          type = types.listOf types.attrs;
          default = [ { } ];
          description = "List of network interfaces currently enabled for passthrough.";
        };
        gpus = mkOption {
          type = types.listOf types.attrs;
          default = [ { } ];
          description = "List of GPUs currently enabled for passthrough.";
        };
        audio = mkOption {
          type = types.listOf types.attrs;
          default = [ { } ];
          description = "List of Audio PCI devices currently enabled for passthrough.";
        };
        usb = mkOption {
          type = types.listOf types.attrs;
          default = [ { } ];
          description = "List of USB devices enabled for passthrough.";
        };
      };
    };
    type = mkOption {
      description = "Type of the ghaf component. One of 'host', 'admin-vm', 'system-vm', or 'app-vm'.";
      type = types.enum [
        "host"
        "admin-vm"
        "system-vm"
        "app-vm"
      ];
    };
    gracefulShutdown = mkOption {
      type = types.bool;
      default = config.ghaf.givc.enable;
      defaultText = "config.ghaf.givc.enable";
      description = ''
        If true, the microvm ExecStop logic for this VM will be overridden
        with the host-managed graceful shutdown, which starts the guest's
        poweroff.target and waits for the VM process to exit.

        This option only has effect if the power manager module is enabled
        on the host:
        `ghaf.services.power-manager.host.enable = true;`
      '';
    };
  };
  config = {

    assertions = lib.flatten (
      map (
        vmName:
        let
          vmAttr = config.ghaf.common.extraNetworking.hosts.${vmName};
        in
        [
          {
            assertion = (vmAttr.cid or null) == null;
            message = "VM '${vmName}' cannot override 'cid'";
          }
          {
            assertion = (vmAttr.name or null) == null;
            message = "VM '${vmName}' cannot override 'name'";
          }

          {
            # Only the host cannot override the internal nic name and mac address
            assertion =
              if vmName == "ghaf-host" then (vmAttr.interfaceName == null && vmAttr.mac == null) else true;
            message = "VM '${vmName}' cannot override 'interfaceName' or 'mac'";
          }
        ]
      ) (builtins.attrNames config.ghaf.common.extraNetworking.hosts)
    );

    # Populate the shared namespace
    ghaf =
      optionalAttrs
        (hasAttrByPath [
          "microvm"
          "vms"
        ] config)
        {
          common = {
            vms = builtins.attrNames config.microvm.vms;
            adminHost =
              let
                adminHosts = lib.lists.remove "" (
                  lib.attrsets.mapAttrsToList (
                    n: v:
                    let
                      vmConfig = lib.ghaf.vm.getConfig v;
                    in
                    lib.optionalString (vmConfig != null && vmConfig.ghaf.type == "admin-vm") n
                  ) config.microvm.vms
                );
              in
              assert builtins.length adminHosts <= 1;
              lib.lists.head (adminHosts ++ [ null ]);
            systemHosts = lib.lists.remove "" (
              lib.attrsets.mapAttrsToList (
                n: v:
                let
                  vmConfig = lib.ghaf.vm.getConfig v;
                in
                lib.optionalString (vmConfig != null && vmConfig.ghaf.type == "system-vm") n
              ) config.microvm.vms
            );
            appHosts = lib.lists.remove "" (
              lib.attrsets.mapAttrsToList (
                n: v:
                let
                  vmConfig = lib.ghaf.vm.getConfig v;
                in
                lib.optionalString (vmConfig != null && vmConfig.ghaf.type == "app-vm") n
              ) config.microvm.vms
            );
            hardware = {
              nics = config.ghaf.hardware.definition.network.pciDevices;
              gpus = config.ghaf.hardware.definition.gpu.pciDevices;
              audio = config.ghaf.hardware.definition.audio.pciDevices;
              usb = config.ghaf.hardware.definition.usb.devices;
            };
          };
        };

    system.stateVersion = lib.trivial.release;

    ####
    # temp means to reduce the image size
    # TODO remove this when the minimal config is defined
    appstream.enable = false;
    boot.enableContainers = false;
    documentation.nixos.enable = false;
    ##### Remove to here

    environment.systemPackages = [
      pkgs.isocodes
    ];

    environment.pathsToLink = [
      "/share/iso-codes"
    ];

    i18n.defaultLocale = "en_US.UTF-8";

    i18n.extraLocales = "all";
  };
}
