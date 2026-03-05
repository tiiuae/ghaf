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
    getExe'
    ;

  # CID values - use option values if set, otherwise look up from hosts
  cid = cfg.vmCid;
  guivmCID = cfg.guivmCid;

  waypipePort = cfg.waypipeBasePort + cid;
  waypipeBaseCmd =
    let
      socket =
        if cfg.serverSocketPath != null then
          "-s ${cfg.serverSocketPath}"
        else
          "--vsock -s ${toString waypipePort}";
    in
    "${getExe pkgs.waypipe} --compress none --no-gpu ${socket}";
  waypipeBorder = strings.optionalString (
    cfg.waypipeBorder && cfg.vm.borderColor != null
  ) "--border \"${cfg.vm.borderColor}\"";

  # Used to run a short-lived Waypipe server for one off connections (e.g. for running a single app through Waypipe)
  runWaypipe = pkgs.writeScriptBin "run-waypipe" ''
    #!${pkgs.runtimeShell} -e
    ${waypipeBaseCmd} server "$@"
  '';

  # Used to run a persistent Waypipe server to fake a Wayland socket for the AppVM
  persistentWaypipeServer = pkgs.writeScriptBin "run-waypipe-persistent" ''
    #!${pkgs.runtimeShell} -e
    ${waypipeBaseCmd} \
    --display ${cfg.persistentWaypipeServer.display} \
    server -- ${pkgs.coreutils}/bin/sleep infinity
  '';
in
{
  _file = ./waypipe.nix;
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

    persistentWaypipeServer = {
      enable = mkEnableOption ''
        Run a single persistent Waypipe server for the AppVM.
        The Waypipe server will be made available at 'WAYLAND_DISPLAY=${cfg.persistentWaypipeServer.display}'.
      '';

      display = mkOption {
        type = types.str;
        default = "wayland-ghaf";
        description = "Name of the persistent Wayland display socket created by waypipe.";
      };

      xDisplay = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = ''
          The X11 display name to use for the XWayland Satellite instance.
          If set to `null`, XWayland Satellite will not be used.

          Note: `waypipe` also supports running xWayland Satellite via the option `--xwls`,
          but the display socket it chooses may be random and therefore unknown to other
          processes on the system.
        '';
      };
    };

    waypipeClientService = mkOption {
      description = ''
        Waypipe client service configuration for this AppVM.
        This service runs in the GUI VM and listens for incoming connections from the AppVM.
      '';
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

  config = mkIf cfg.enable (
    lib.mkMerge [
      {
        environment.systemPackages = [
          pkgs.waypipe
          runWaypipe
        ];

        hardware.graphics.enable = true;

        ghaf.waypipe = {
          waypipeClientService = {
            enable = true;
            description = "Waypipe Client Service For ${cfg.vm.name}";
            serviceConfig = {
              Type = "simple";
              Restart = "always";
              RestartSec = "1";
              ExecStart =
                let
                  titlePrefix = ''--title-prefix "[${cfg.vm.name}-vm] "'';
                  secctx = "--secctx \"${cfg.vm.name}\"";
                in
                ''
                  ${waypipeBaseCmd} ${titlePrefix} ${secctx} ${waypipeBorder} client
                '';
            };
            startLimitIntervalSec = 0;
            partOf = [ "ghaf-session.target" ];
            wantedBy = [ "ghaf-session.target" ];
          };

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
      }

      (mkIf cfg.persistentWaypipeServer.enable {
        environment.systemPackages = [
          persistentWaypipeServer
          pkgs.xwayland-satellite
        ];

        environment.sessionVariables = {
          WAYLAND_DISPLAY = cfg.persistentWaypipeServer.display;
          DISPLAY = mkIf (cfg.persistentWaypipeServer.xDisplay != null) cfg.persistentWaypipeServer.xDisplay;
        };

        systemd.user.services = {
          waypipe-server = {
            description = "Persistent Waypipe Wayland Socket Forwarder";
            wantedBy = [ "default.target" ];
            unitConfig = {
              ConditionUser = config.ghaf.users.appUser.name;
            };
            serviceConfig = {
              Type = "exec";
              ExecStart = "${getExe persistentWaypipeServer}";
              ExecStopPost = "rm -f %t/${cfg.persistentWaypipeServer.display}";
              Restart = "on-failure";
              RestartSec = "2s";
            };
          };

          waypipe-server-env = {
            description = "Waypipe Display env var Exporter";
            wantedBy = [ "waypipe-server.service" ];
            after = [ "waypipe-server.service" ];
            unitConfig = {
              ConditionUser = config.ghaf.users.appUser.name;
            };
            serviceConfig = {
              Type = "oneshot";
              RemainAfterExit = true;
              ExecStart = ''
                ${getExe' pkgs.systemd "systemctl"} --user set-environment \
                WAYLAND_DISPLAY=${cfg.persistentWaypipeServer.display} \
                DISPLAY=${cfg.persistentWaypipeServer.xDisplay} \
                XDG_SESSION_TYPE=wayland
              '';
            };
          };

          # XWayland Satellite allows X11 apps to run in the AppVM and display through the persistent Waypipe server
          xwayland-satellite = {
            enable = cfg.persistentWaypipeServer.xDisplay != null;
            description = "XWayland Satellite";
            wantedBy = [ "waypipe-server.service" ];
            after = [ "waypipe-server.service" ];
            unitConfig = {
              ConditionUser = config.ghaf.users.appUser.name;
            };
            serviceConfig = {
              Type = "notify";
              ExecStart = ''
                ${lib.getExe pkgs.xwayland-satellite} ${cfg.persistentWaypipeServer.xDisplay}
              '';
              Restart = "on-failure";
              RestartSec = "5s";
            };
          };
        };
      })
    ]
  );
}
