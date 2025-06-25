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

  xwaylandLabwcRc = pkgs.writeText "xwayland-labwc-rc" ''
    <?xml version="1.0"?>
    <labwc_config>
      <theme>
        <!-- don’t keep the thin safety rim -->
        <keepBorder>no</keepBorder>      <!-- default is yes -->
        <!-- make the border width literally zero -->
        <border><width>0</width></border>
      </theme>
      <core>
        <decoration>client</decoration>
      </core>
      <windowRules>
        <!-- Make app applications full screen without borders -->
        <windowRule identifier="*" type="normal">
          <!--<serverDecoration>no</serverDecoration>-->
          <action name="ToggleFullscreen"/>
        </windowRule>

        <!-- Ensure dialogs and menus are always visible -->
        <windowRule type="dialog">
          <action name="ToggleAlwaysOnTop"/>
          <action name="Raise"/>
        </windowRule>
        <windowRule type="popup_menu"><action name="ToggleAlwaysOnTop"/></windowRule>
        <windowRule type="dropdown_menu"><action name="ToggleAlwaysOnTop"/></windowRule>
        <windowRule type="tooltip"><action name="ToggleAlwaysOnTop"/></windowRule>
      </windowRules>
    </labwc_config>
  '';

  runWaypipe = pkgs.writeShellApplication {
    name = "run-waypipe";
    runtimeInputs = with pkgs; [
      waypipe
      labwc
      xwayland
    ];
    text =
      let
        socket =
          if cfg.serverSocketPath != null then
            "--socket ${cfg.serverSocketPath}"
          else
            "--vsock -s ${toString waypipePort}";
      in
      ''
        if [ "$1" = "--help" ] || [ "$1" = "-h" ]; then
          echo "usage: run-waypipe [-X] <application> [args...]"
          echo "  -X: support running with XWayland (through a sub-compositor)"
          exit 0;
        fi

        if [ "$1" = "-X" ]; then
          waypipe ${socket} server "labwc" -c ${xwaylandLabwcRc}/xwayland-labwc-rc -S "''${@:2}"
        else
          waypipe ${socket} server "$@"
        fi

      '';
  };

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
              titlePrefix = lib.optionalString (
                config.ghaf.profiles.graphics.compositor == "cosmic"
              ) ''--title-prefix "[${cfg.vm.name}-vm] "'';
              secctx = "--secctx \"${cfg.vm.name}\"";
              socketPath =
                if cfg.serverSocketPath != null then
                  "-s ${cfg.serverSocketPath} client"
                else
                  "--vsock -s ${toString waypipePort} client";
            in
            ''
              ${pkgs.waypipe}/bin/waypipe ${titlePrefix} ${secctx} ${waypipeBorder} ${socketPath}
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
          ExecStart = "${pkgs.vsockproxy}/bin/vsockproxy ${toString waypipePort} ${toString guivmCID} ${toString waypipePort} ${toString cid}";
        };
        startLimitIntervalSec = 0;
        wantedBy = [ "multi-user.target" ];
      };
    };
  };
}
