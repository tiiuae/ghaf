# Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# TODO: Refactor even more.
#       This is the old "host/default.nix" file.
#
# ghaf.common: Interface to share ghaf configs from host to VMs
#
{ config, lib, ... }:
let
  inherit (builtins) attrNames;
  inherit (lib)
    mkOption
    types
    optionalAttrs
    optionalString
    attrsets
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

    i18n.supportedLocales = [
      "C.UTF-8/UTF-8"
      "en_US.UTF-8/UTF-8"
      "ar_AE.UTF-8/UTF-8"
    ];
    environment.extraInit = ''
      if [ -f /etc/locale.conf ]; then
          . /etc/locale.conf
          export LANG LC_CTYPE LC_NUMERIC LC_TIME LC_COLLATE LC_MONETARY LC_MESSAGES LC_PAPER LC_NAME LC_ADDRESS LC_TELEPHONE LC_MEASUREMENT LC_IDENTIFICATION LC_ALL
      fi
    '';

  };
}
