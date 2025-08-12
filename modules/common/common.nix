# Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
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
  inherit (builtins) attrNames;
  inherit (lib)
    mkOption
    types
    optionalAttrs
    hasAttrByPath
    ;
in
{
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
      vms = mkOption {
        type = types.listOf types.str;
        default = [ ];
        description = "List of VMs currently enabled.";
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
      };
    };
    type = mkOption {
      description = "Type of the ghaf component. One of 'host', 'system-vm', or 'app-vm'.";
      type = types.enum [
        "host"
        "system-vm"
        "app-vm"
      ];
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
            vms = attrNames config.microvm.vms;
            systemHosts = lib.lists.remove "" (
              lib.attrsets.mapAttrsToList (
                n: v: lib.optionalString (v.config.config.ghaf.type == "system-vm") n
              ) config.microvm.vms
            );
            appHosts = lib.lists.remove "" (
              lib.attrsets.mapAttrsToList (
                n: v: lib.optionalString (v.config.config.ghaf.type == "app-vm") n
              ) config.microvm.vms
            );
            hardware = {
              nics = config.ghaf.hardware.definition.network.pciDevices;
              gpus = config.ghaf.hardware.definition.gpu.pciDevices;
              audio = config.ghaf.hardware.definition.audio.pciDevices;
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
