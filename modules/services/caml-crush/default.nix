# Copyright 2022-2023 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# Module for caml-crush systemd service
#
{
  lib,
  pkgs,
  config,
  ...
}: let
  cfg = config.ghaf.services.caml-crush;

  defaultUser = "caml-crush";
  defaultGroup = defaultUser;

  # Used when caml-crush is built using --without-filter
  libnamesConfig = lib.concatStrings (lib.mapAttrsToList (a: b: "${a}:${b};") cfg.pkcs11Modules);

  # Used when caml-crush is built with filter
  filterModules = lib.concatStringsSep ", " (lib.mapAttrsToList (a: b: ''("${a}", "${b}")'') cfg.pkcs11Modules);
  filterConfig = pkgs.substituteAll {
    src = ./filter.conf;
    inherit (cfg) filterDebugLevel filterExtraConfig;
    inherit filterModules;
  };

  # Processor needs to be configured very differently if filtering is not used
  processor =
    if cfg.disableFilter
    then ''libnames = "${libnamesConfig}";''
    else ''filter_config = "${filterConfig}";'';

  # Generate the main config file
  pkcs11proxydConf = pkgs.substituteAll {
    src = ./pkcs11proxyd.conf;
    inherit processor;
  };

  # List of libnames wrappers to generate
  libnames = builtins.attrNames cfg.pkcs11Modules;

  packageWithOverrides = (cfg.package.overrideAttrs
    (prev: {
      configureFlags =
        prev.configureFlags
        ++ [
          "--with-libnames=${builtins.concatStringsSep "," libnames}"
          "--with-client-socket=${cfg.clientSocket}"
        ]
        ++ lib.optionals cfg.disableFilter [
          "--without-filter"
        ];
    }))
  .override {ocamlClient = cfg.enableOcamlClient;};

  mkPkcs11ToolWrapper = libname:
    pkgs.writeShellScriptBin "pkcs11-tool-caml-crush-${libname}" ''
      exec "${pkgs.opensc}/bin/pkcs11-tool" --module "${packageWithOverrides}/lib/caml-crush/libp11client${libname}.so" $@
    '';
in {
  options.ghaf.services.caml-crush = {
    enable = lib.mkEnableOption "caml-crush";

    clientSocket = lib.mkOption {
      type = lib.types.str;
      default = "tcp,127.0.0.1:4444";
      example = "unix,/run/pkcs11-socket";
      description = lib.mdDoc ''
        Client socket configruation. You can specify either UNIX domain socket or TCP socket.

        Example of UNIX domain socket: `unix,/run/pkcs11-socket`
        Example of TCP socket: `tcp,127.0.0.1:4444`
      '';
    };

    disableFilter = lib.mkEnableOption ''
      to configure build without filter. According to caml-crush documentation,
      not recommended in production use.
    '';

    filterDebugLevel = lib.mkOption {
      type = lib.types.int;
      default = 0;
      example = 7;
      description = lib.mdDoc ''
        Debug level for filter configuration.
      '';
    };

    filterExtraConfig = lib.mkOption {
      type = lib.types.str;
      default = "";
      example = ''
        filter_actions_post = [ (".*",
          [
           (******** This is optional: key usage segregation ******************************)
           (* (C_Initialize, do_segregate_usage), *)

           (******** Check for key creation and attribute manipulation on non local keys **)
           (C_CreateObject, non_local_objects_patch),
           (C_CopyObject, non_local_objects_patch),
           (C_SetAttributeValue, non_local_objects_patch),

           ...

          ]
         )
        ]
      '';
      description = lib.mdDoc ''
        The filter configuration. By default there is no filtering, even when
        the filtering module is enabled. User of this module is supposed to
        configure the filter using this option.
      '';
    };

    enableOcamlClient = lib.mkEnableOption "the hybrid OCaml/C client library";

    package = lib.mkOption {
      type = lib.types.package;
      default = pkgs.callPackage ../../../user-apps/caml-crush {};
      defaultText = lib.literalExpression "pkgs.callPackage ../../../user-apps/caml-crush {};";
      description = lib.mdDoc "The package to use for the caml-crush.";
    };

    user = lib.mkOption {
      type = lib.types.str;
      default = defaultUser;
      example = defaultUser;
      description = lib.mdDoc ''
        The user for the service. If left as the default value this user will
        automatically be created.
      '';
    };

    group = lib.mkOption {
      type = lib.types.str;
      default = defaultGroup;
      example = defaultGroup;
      description = lib.mdDoc ''
        The group for the service. If left as the default value this group will
        automatically be created.
      '';
    };

    # Option to point to the pkcs11 .so file
    pkcs11Modules = lib.mkOption {
      type = lib.types.attrsOf lib.types.string;
      default = {};
      example = ''
        { "optee" = "NIX_STORE_PATH/lib/libckteek.so"; }
      '';
      description = lib.mdDoc ''
        Configures libnames and paths of PKCS#11 modules to be used by the proxy.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    users = {
      users = lib.mkIf (cfg.user == defaultUser) {
        "${defaultUser}" = {
          group = cfg.group;
          isSystemUser = true;
        };
      };
      groups = lib.mkIf (cfg.group == defaultGroup) {
        "${defaultGroup}" = {};
      };
    };
    systemd.services.caml-crush = {
      enable = true;
      description = "Caml Crush: an OCaml PKCS#11 filtering proxy";
      path = [packageWithOverrides];
      serviceConfig = {
        User = cfg.user;
        Group = cfg.group;
        Type = "simple";
        StandardOutput = "journal";
        StandardError = "journal";
        ExecStart = lib.concatStringsSep " " [
          "${packageWithOverrides}/bin/pkcs11proxyd"
          "-fg"
          "-conf"
          "${pkcs11proxydConf}"
        ];
        Restart = "always";
      };
      after = ["tee-supplicant.service"];
      wantedBy = ["multi-user.target"];
    };

    environment.systemPackages = builtins.map mkPkcs11ToolWrapper libnames;

    # Permissions for /dev/tee0
    # TODO: Create separate group for tee-client, and add user of the
    #       caml-crush service to that group.
    services.udev.extraRules = ''
      SUBSYSTEM=="tee",KERNEL=="tee0",GROUP="${cfg.group}"
    '';
  };
}
