# Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.ghaf.waypipe;

  inherit (lib)
    mkEnableOption
    mkOption
    mkIf
    types
    strings
    ;

  inherit (config.ghaf.networking.hosts."${cfg.vm.name}-vm") cid;
  guivmCID = config.ghaf.networking.hosts.gui-vm.cid;

  waypipePort = cfg.waypipeBasePort + cid;
  waypipeBorder = strings.optionalString (
    cfg.waypipeBorder && cfg.vm.borderColor != null
  ) "--border \"${cfg.vm.borderColor}\"";
  serverSocketPath =
    if cfg.serverSocketPath != null then cfg.serverSocketPath "gui" "-${cfg.vm.name}-vm" else null;
  runWaypipe =
    let
      script =
        if cfg.serverSocketPath != null then
          ''
            #!${pkgs.runtimeShell} -e
            ${pkgs.waypipe}/bin/waypipe -s ${cfg.clientSocketPath} server "$@"
          ''
        else
          ''
            #!${pkgs.runtimeShell} -e
            ${pkgs.waypipe}/bin/waypipe --vsock -s ${toString waypipePort} server "$@"
          '';
    in
    pkgs.writeScriptBin "run-waypipe" script;

in
{
  options.ghaf.waypipe = {
    enable = mkEnableOption "Waypipe support";

    vm = mkOption {
      description = "The appvm submodule definition";
      type = types.attrs;
      # TODO should we centralize submodules?
      default = { };
    };

    proxyService = mkOption {
      description = "vsockproxy service configuration for the AppVM";
      type = types.attrs;
      readOnly = true;
      visible = false;
    };

    waypipeService = mkOption {
      description = "Waypipe service configuration for the AppVM";
      type = types.attrs;
      readOnly = true;
      visible = false;
    };

    waypipeBorder = mkEnableOption "Waypipe window border";

    # Every AppVM has its own instance of Waypipe running in the GUIVM and
    # listening for incoming connections from the AppVM on its own port.
    # The port number each AppVM uses is waypipeBasePort + vm CID.
    waypipeBasePort = mkOption {
      description = "Waypipe base port number for AppVMs";
      type = types.int;
      readOnly = true;
      default = 1100;
    };

    clientSocketPath = mkOption {
      description = "Waypipe client socket path";
      type = types.nullOr types.path;
      default = null;
    };

    serverSocketPath = mkOption {
      description = "Waypipe server socket path";
      type = types.nullOr (types.functionTo (types.functionTo types.path));
      default = null;
    };
  };

  config = mkIf cfg.enable {

    environment.systemPackages = [
      pkgs.waypipe
      runWaypipe
    ];

    # Ensure that the vulkan drivers are available for the waypipe to utilize
    # it is already available in the GUIVM so this will ensure it is there in the appvms that enable the waypipe only.
    hardware.graphics.enable = true;

    ghaf.waypipe = {
      # Waypipe service runs in the GUIVM and listens for incoming connections from AppVMs
      waypipeService = {
        enable = true;
        description = "Waypipe for ${cfg.vm.name}";
        serviceConfig = {
          Type = "simple";
          Restart = "always";
          RestartSec = "1";
          ExecStart =
            let
              titlePrefix = lib.optionalString (
                config.ghaf.profiles.graphics.compositor == "cosmic"
              ) ''--title-prefix "[${cfg.vm.name}-vm] "'';
              secctx = "--secctx \"${cfg.vm.name}\"";
              socketPath =
                if cfg.serverSocketPath != null then
                  "-s ${serverSocketPath} client"
                else
                  "--vsock -s ${toString waypipePort} client";
            in
            ''
              ${pkgs.waypipe}/bin/waypipe ${titlePrefix} ${secctx} ${waypipeBorder} ${socketPath}
            '';
          KillSignal = "SIGINT";
        };
        startLimitIntervalSec = 0;
        partOf = [ "ghaf-session.target" ];
        wantedBy = [ "ghaf-session.target" ];
      };

      # vsockproxy is used on host to forward data between AppVMs and GUIVM
      proxyService = {
        enable = true;
        description = "vsockproxy for ${cfg.vm.name}";
        serviceConfig = {
          Type = "simple";
          Restart = "always";
          RestartSec = "1";
          ExecStart = "${pkgs.vsockproxy}/bin/vsockproxy ${toString waypipePort} ${toString guivmCID} ${toString waypipePort} ${toString cid}";
        };
        startLimitIntervalSec = 0;
        wantedBy = [ "multi-user.target" ];
      };
    };
  };
}
