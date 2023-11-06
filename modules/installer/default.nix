# Copyright 2022-2023 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
inputs @ {
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.ghaf.installer;
in {
  options.ghaf.installer = {
    enable = lib.mkEnableOption "installer image";

    imgModules = lib.mkOption {
      description = lib.mdDoc ''
        Modules that will be passed to the installer image.
      '';
      type = with lib.types; listOf deferredModule;
      default = [];
    };

    # NOTE: These options tries to resemble calamares module system so we'll be
    # able to generate calamares installer from same (almost) code base.
    # TODO: Add library of bash functions with unified way of asking user
    # required information.
    installerModules = lib.mkOption {
      description = lib.mdDoc ''
        Modules describe the information requested from the user
        for the installer.

        All code must be written for the current pkgs.runtimeShell.
      '';
      type = with lib.types;
        attrsOf (submodule {
          options = {
            requestCode = lib.mkOption {
              description = lib.mdDoc ''
                Code that will ask user their preferences.
              '';
              type = lines;
              default = "echo \"Here's should be your installer\"";
            };
            providedVariables = lib.mkOption {
              description = lib.mdDoc ''
                Variable that this modules provides.
                Used to detect errors with non-existent variables.
              '';
              type = attrsOf str;
              default = {};
            };
          };
        });
    };

    enabledModules = lib.mkOption {
      description = lib.mdDoc ''
        Sequence of enabled modules.
      '';
      type = with lib.types; listOf str;
      default = [];
    };

    installerCode = lib.mkOption {
      description = lib.mdDoc ''
        Code that will install image based on the information
        collected from the installer modules.

        All code must be written for the current pkgs.runtimeShell.
      '';
      type = lib.types.lines;
      default = "";
    };
  };

  config = lib.mkIf cfg.enable (let
    builtinModulesPaths = map (name: "${./builtin}/${name}.nix") ["flush"];
    modulePath2Module = path: import path inputs;
    builtinInstallerModules = map modulePath2Module builtinModulesPaths;
  in
    builtins.foldl' lib.recursiveUpdate {
      system.build.installer = let
        name2code = name: cfg.installerModules.${name}.requestCode;
        enabledModulesCode = map name2code cfg.enabledModules;
        enabledModulesCode' = builtins.concatStringsSep "\n" enabledModulesCode;
      in
        (lib.ghaf.installer {
          systemImgCfg = config;
          modules = cfg.imgModules;
          userCode = ''
            # Modules code
            ${enabledModulesCode'}

            # Installer code
            ${cfg.installerCode}
          '';
        })
        .installerImgDrv;
    }
    builtinInstallerModules);
}
