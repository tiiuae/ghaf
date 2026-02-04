# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
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
    getExe
    ;

  # CID values - use option values if set, otherwise look up from hosts
  cid = cfg.vmCid;
  guivmCID = cfg.guivmCid;

  waypipeBaseCmd = "${getExe pkgs.waypipe} --compress none --no-gpu";
  waypipePort = cfg.waypipeBasePort + cid;
  waypipeBorder = strings.optionalString (
    cfg.waypipeBorder && cfg.vm.borderColor != null
  ) "--border \"${cfg.vm.borderColor}\"";
  runWaypipe =
    let
      script =
        if cfg.serverSocketPath != null then
          ''
            #!${pkgs.runtimeShell} -e
            ${waypipeBaseCmd} -s ${cfg.serverSocketPath} server "$@"
          ''
        else
          ''
            #!${pkgs.runtimeShell} -e
            ${waypipeBaseCmd} --vsock -s ${toString waypipePort} server "$@"
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

    vmCid = mkOption {
      description = "CID of this VM for vsock communication";
      type = types.int;
      default =
        if config.ghaf.networking.hosts ? "${cfg.vm.name}-vm" then
          config.ghaf.networking.hosts."${cfg.vm.name}-vm".cid
        else
          0;
    };

    guivmCid = mkOption {
      description = "CID of the GUI VM for vsock communication";
      type = types.int;
      default =
        if config.ghaf.networking.hosts ? "gui-vm" then config.ghaf.networking.hosts."gui-vm".cid else 3;
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

    serverSocketPath = mkOption {
      description = "Waypipe server socket path";
      type = types.nullOr types.str;
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
              titlePrefix = ''--title-prefix "[${cfg.vm.name}-vm] "'';
              secctx = "--secctx \"${cfg.vm.name}\"";
              socketPath =
                if cfg.serverSocketPath != null then
                  "-s ${cfg.serverSocketPath} client"
                else
                  "--vsock -s ${toString waypipePort} client";
            in
            ''
              ${waypipeBaseCmd} ${titlePrefix} ${secctx} ${waypipeBorder} ${socketPath}
            '';
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
          ExecStart = "${getExe pkgs.vsockproxy} ${toString waypipePort} ${toString guivmCID} ${toString waypipePort} ${toString cid}";
        };
        startLimitIntervalSec = 0;
        wantedBy = [ "multi-user.target" ];
      };
    };
  };
}
