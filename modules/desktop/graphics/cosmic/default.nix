# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  lib,
  pkgs,
  config,
  ...
}:
let
  inherit (lib)
    mkIf
    mkEnableOption
    mkOption
    types
    getExe
    literalExpression
    ;

  cfg = config.ghaf.graphics.cosmic;
  graphicsProfileCfg = config.ghaf.profiles.graphics;

  ghaf-cosmic-config = import ./config/cosmic-config.nix {
    inherit lib pkgs;
    inherit (cfg)
      topPanelApplets
      bottomPanelApplets
      panels
      extraShortcuts
      disabledShortcuts
      systemActions
      ;
    idle =
      let
        ms = v: if cfg.idleManagement.enable then v * 1000 else 0;
      in
      {
        screenOffTime = ms cfg.idleManagement.screenOffTime;
        suspendOnBattery = ms cfg.idleManagement.suspendOnBattery;
        suspendOnAC = ms cfg.idleManagement.suspendOnAC;
      };
    secctx = cfg.securityContext;
  };

  autostart = pkgs.writeShellApplication {
    name = "autostart";

    text = "" + cfg.extraAutostart;
  };

  # Change papirus folder icons to grey
  papirus-icon-theme-grey = pkgs.papirus-icon-theme.override {
    color = "grey";
    # The following fixes a cross-compilation issue
    inherit (pkgs.buildPackages) papirus-folders;
  };
in
{
  _file = ./default.nix;

  options.ghaf.graphics.cosmic = {
    enable = mkEnableOption "the COSMIC desktop environment in Ghaf";

    idleManagement = {
      enable = mkOption {
        type = types.bool;
        default = graphicsProfileCfg.idleManagement.enable;
        defaultText = literalExpression "config.ghaf.profiles.graphics.idleManagement.enable";
        description = ''
          Whether to enable idle management.

          When enabled, the system will automatically manage screen blanking and suspension
          based on user inactivity.

          If disabled, the default timeouts will be set to 'Never'.
          However, users can still manually configure the settings via COSMIC Settings to override this behavior.

          If 'config.ghaf.services.power-manager.suspend.enable' is false, suspension will not occur
          regardless of this setting.
        '';
      };
      screenOffTime = mkOption {
        type = types.int;
        default =
          if cfg.idleManagement.enable then
            300 # 5 minutes by default
          else
            0;
        description = ''
          Time in seconds of inactivity before the screen is turned off and the session is locked.
        '';
      };
      suspendOnBattery = mkOption {
        type = types.int;
        default = cfg.idleManagement.screenOffTime * 3; # 15 minutes by default
        defaultText = literalExpression "config.ghaf.graphics.cosmic.idleManagement.screenOffTime * 3";
        description = ''
          Time in seconds of inactivity before the system suspends when on battery power.
        '';
      };
      suspendOnAC = mkOption {
        type = types.int;
        default = cfg.idleManagement.screenOffTime * 3; # 15 minutes by default
        defaultText = literalExpression "config.ghaf.graphics.cosmic.idleManagement.screenOffTime * 3";
        description = ''
          Time in seconds of inactivity before the system suspends when on AC power.
        '';
      };
    };

    securityContext = mkOption {
      type = types.submodule {
        options = {
          borderWidth = mkOption {
            type = types.ints.positive;
            default = 6;
            example = 6;
            description = "Default border width in pixels";
          };

          rules = mkOption {
            type = types.listOf (
              types.submodule {
                options = {
                  identifier = mkOption {
                    type = types.str;
                    example = "chrome-vm";
                    description = "The identifier attached to the security context";
                  };
                  color = mkOption {
                    type = types.str;
                    example = "#006305";
                    description = "Window border color";
                  };
                };
              }
            );
            description = "List of security contexts rules";
          };
        };
      };
      default = {
        borderWidth = 4;
        rules = [ ];
      };
      description = "Security context settings";
    };

    topPanelApplets = mkOption {
      type = types.submodule {
        options = {
          left = lib.mkOption {
            description = "List of applets to show on the left side of the panel.";
            type = types.listOf types.str;
            default = [ ];
          };
          center = lib.mkOption {
            description = "List of applets to show in the center of the panel.";
            type = types.listOf types.str;
            default = [ ];
          };
          right = lib.mkOption {
            description = "List of applets to show on the right side of the panel.";
            type = types.listOf types.str;
            default = [ ];
          };
        };
      };
      default = {
        left = [
          "com.system76.CosmicPanelAppButton"
          "com.system76.CosmicPanelWorkspacesButton"
        ];
        center = [
          "com.system76.CosmicAppletTime"
          "com.system76.CosmicAppletNotifications"
        ];
        right = [
          "com.system76.CosmicAppletInputSources"
          "com.system76.CosmicAppletStatusArea"
          "ae.tii.CosmicAppletKillSwitch"
          "com.system76.CosmicAppletTiling"
          "com.system76.CosmicAppletNetwork"
          "com.system76.CosmicAppletAudio"
          "com.system76.CosmicAppletBattery"
          "com.system76.CosmicAppletPower"
        ];
      };
      description = ''
        Cosmic top panel applets configuration.

        Used only when the top and bottom panel layout is selected.
      '';
    };

    bottomPanelApplets = mkOption {
      type = types.submodule {
        options = {
          left = lib.mkOption {
            description = "List of applets to show on the left side of the panel.";
            type = types.listOf types.str;
            default = [ ];
          };
          center = lib.mkOption {
            description = "List of applets to show in the center of the panel.";
            type = types.listOf types.str;
            default = [ ];
          };
          right = lib.mkOption {
            description = "List of applets to show on the right side of the panel.";
            type = types.listOf types.str;
            default = [ ];
          };
        };
      };
      default = {
        left = [
          "com.system76.CosmicPanelAppButton"
          "com.system76.CosmicPanelWorkspacesButton"
          "com.system76.CosmicAppList"
          "com.system76.CosmicAppletMinimize"
        ];
        # Keep center empty when using bottom-only panel
        center = [ ];
        right = [
          "com.system76.CosmicAppletInputSources"
          "com.system76.CosmicAppletStatusArea"
          "ae.tii.CosmicAppletKillSwitch"
          "com.system76.CosmicAppletTiling"
          "com.system76.CosmicAppletNetwork"
          "com.system76.CosmicAppletAudio"
          "com.system76.CosmicAppletBattery"
          "com.system76.CosmicAppletNotifications"
          "com.system76.CosmicAppletTime"
          "com.system76.CosmicAppletPower"
        ];
      };
      description = ''
        Cosmic top panel applets configuration.

        Used only when the bottom-only panel layout is selected.
      '';
    };

    extraShortcuts = mkOption {
      type = types.listOf (
        types.submodule {
          options = {
            modifiers = mkOption {
              type = types.listOf types.str;
              default = [ ];
              description = "COSMIC modifier names, for example `[ \"Super\" \"Shift\" ]`.";
            };
            key = mkOption {
              type = types.str;
              description = "Key name as COSMIC spells it, for example `r` or `XF86LaunchA`.";
            };
            command = mkOption {
              type = types.str;
              description = "Command to spawn when the shortcut is pressed.";
            };
          };
        }
      );
      default = lib.optionals cfg.screenRecorder.enable [
        {
          modifiers = [
            "Ctrl"
            "Shift"
            "Alt"
          ];
          key = "r";
          command = "ghaf-screen-record";
        }
      ];
      defaultText = literalExpression "the screen recorder binding when `screenRecorder.enable`";
      description = ''
        Shortcuts appended to COSMIC's defaults, each spawning a command.
      '';
    };

    disabledShortcuts = mkOption {
      type = types.listOf types.str;
      default = [ ];
      example = literalExpression ''[ "System(AppLibrary)" "System(Launcher)" ]'';
      description = ''
        COSMIC actions to disable, named exactly as they appear on the
        right-hand side of a binding in the shipped shortcut defaults.

        Every binding for a named action is disabled, which is why this names
        actions rather than bindings: `System(AppLibrary)` is bound both to
        `Super+A` and to `Super` alone, and `System(WorkspaceOverview)` to
        `Super+W` and to the `XF86LaunchA` key some keyboards have. Naming an
        action that no binding uses fails the build, so the list cannot go
        stale unnoticed when a default binding changes.

        Bindings that are not named keep working; this is a partial override.
      '';
    };

    systemActions = mkOption {
      type = types.attrsOf types.str;
      default = { };
      example = literalExpression ''{ Launcher = ""; AppLibrary = ""; }'';
      description = ''
        Overrides for COSMIC's system actions, keyed by action name. The value
        is run as `sh -c "<value>"`, so `""` is a working no-op.

        Actions that are not named keep their values. Naming an action COSMIC
        does not have fails the build.

        Disabling the bindings for an action and neutering the action itself
        are worth doing together: the first covers the bindings shipped today,
        the second also covers a dedicated key or a binding a later COSMIC
        adds.
      '';
    };

    panels = mkOption {
      type = types.listOf (
        types.enum [
          "Panel"
          "Dock"
        ]
      );
      default = [
        "Panel"
        "Dock"
      ];
      example = literalExpression "[ ]";
      description = ''
        Which COSMIC panels the session has. `[ ]` produces a session with
        neither panel nor dock.

        Applies to the selectable panel layouts as well, so a layout cannot
        restore a panel that was removed here. Applet options for an absent
        panel are a no-op.

        This is build-time only. Toggling panels within a running session is
        not supported; see the COSMIC reference documentation for why.
      '';
    };

    renderDevice = mkOption {
      type = types.nullOr types.path;
      default = null;
      defaultText = "null";
      example = "/dev/dri/renderD129";
      description = ''
        Path to the render device to be used by the COSMIC compositor.

        If set, this will be assigned to the `COSMIC_RENDER_DEVICE` environment variable,
        directing COSMIC to use the specified device (e.g., /dev/dri/renderD129).

        This option can be useful in systems with multiple GPUs to explicitly select
        which device the compositor should use.

        If unset, COSMIC will attempt to automatically detect a suitable render device.
      '';
    };

    screenRecorder.enable =
      lib.mkEnableOption "screen recording capabilities using gpu-screen-recorder"
      // {
        default = true;
      };

    extraAutostart = lib.mkOption {
      type = lib.types.str;
      default = "";
      description = "Additional shell commands to run on ghaf COSMIC session start-up.";
    };
  };

  config = mkIf cfg.enable {
    services = {
      desktopManager.cosmic.enable = true;
      displayManager.cosmic-greeter.enable = true;
    };

    ghaf.graphics = {
      login-manager.enable = true;
      login-manager.failLock.enable = true;
    };

    ghaf.graphics.screen-recorder.enable = cfg.screenRecorder.enable;

    environment = {
      systemPackages =
        with pkgs;
        [
          papirus-icon-theme-grey
          adwaita-icon-theme
          ghaf-wallpapers
          grim # promptless screenshot for test automation
          (import ../launchers-pkg.nix { inherit pkgs config lib; })
        ]
        ++ [ (lib.hiPrio ghaf-cosmic-config) ];
      sessionVariables = {
        XDG_CONFIG_HOME = "$HOME/.config";
        XDG_DATA_HOME = "$HOME/.local/share";
        XDG_STATE_HOME = "$HOME/.local/state";
        XDG_CACHE_HOME = "$HOME/.cache";
        XDG_PICTURES_DIR = "$HOME/Pictures";
        XDG_VIDEOS_DIR = "$HOME/Videos";
        XCURSOR_THEME = "Cosmic";
        XCURSOR_SIZE = 24;
        RUST_LOG = "error";
      }
      // lib.optionalAttrs (cfg.renderDevice != null) {
        COSMIC_RENDER_DEVICE = cfg.renderDevice;
      };

      etc = {
        # Which XDG directories to create by default
        # Uncomment the ones we want to create
        "xdg/user-dirs.defaults".text = ''
          #DOWNLOAD=Downloads
          #DOCUMENTS=Documents
          #MUSIC=Music
          PICTURES=Pictures
          VIDEOS=Videos
          #PUBLICSHARE=Public
          #TEMPLATES=Templates
          #DESKTOP=Desktop
        '';
      };
    };

    # Remove fira, as it's unused
    fonts.packages = lib.mkForce (
      with pkgs;
      [
        noto-fonts
        open-sans
      ]
    );

    ghaf.services.power-manager.suspend.extraResumeCommands =
      # Workaround for https://github.com/pop-os/cosmic-applets/issues/1390
      # TODO: Remove when upstream issue is fixed
      ''
        # The NetworkManager D-Bus proxy and forwarded PipeWire core recover
        # asynchronously after net-vm and audio-vm resume. Restarting the panel
        # before they accept requests leaves their applets permanently empty.
        if systemctl -q is-enabled dbus-proxy-networkmanager.service; then
          ${lib.getExe' pkgs.coreutils "timeout"} 30 ${lib.getExe pkgs.bash} -c '
            until ${lib.getExe' pkgs.systemd "busctl"} --system get-property \
              org.freedesktop.NetworkManager \
              /org/freedesktop/NetworkManager \
              org.freedesktop.NetworkManager State >/dev/null 2>&1; do
              ${lib.getExe' pkgs.coreutils "sleep"} 0.5
            done
          ' || echo "NetworkManager proxy did not recover before the panel restart"
        fi

        if [ -S /tmp/pipewire-0 ]; then
          ${lib.getExe' pkgs.coreutils "timeout"} 30 ${lib.getExe pkgs.bash} -c '
            until PIPEWIRE_RUNTIME_DIR=/tmp ${lib.getExe' pkgs.coreutils "timeout"} 2 \
              ${lib.getExe' pkgs.wireplumber "wpctl"} status >/dev/null 2>&1; do
              ${lib.getExe' pkgs.coreutils "sleep"} 0.5
            done
          ' || echo "PipeWire control did not recover before the panel restart"
        fi

        pid=$(${lib.getExe' pkgs.busybox "pgrep"} -f "cosmic-panel" | ${lib.getExe' pkgs.busybox "head"} -n1)
        if [ -n "$pid" ]; then
          ${lib.getExe' pkgs.busybox "kill"} "$pid" || true
        else
          echo "No COSMIC panel PID found"
        fi
        #
        # Workaround for volume slider not working and volume panels not showing after resume
        # zlink 0.7.0 fixes the COSMIC settings daemon resume issue.
        # TODO: Remove when zlink ≥ 0.7.0 is used by COSMIC (currently it's 0.5.0)
        # COSMIC Cargo.lock reference:
        # https://github.com/pop-os/cosmic-settings/blob/master/Cargo.lock#L9383
        # Restart COSMIC settings daemon after suspend, as it may not resume properly on some systems
        pid=$(${lib.getExe' pkgs.busybox "pgrep"} -f "cosmic-settings-daemon" | ${lib.getExe' pkgs.busybox "head"} -n1)
        if [ -n "$pid" ]; then
          ${lib.getExe' pkgs.busybox "kill"} -9 "$pid" || true
        else
          echo "No COSMIC settings daemon PID found"
        fi
      '';

    systemd.user.services = {
      autostart = {
        description = "Ghaf autostart";
        serviceConfig.ExecStart = "${getExe autostart}";
        partOf = [ "cosmic-session.target" ];
        wantedBy = [ "cosmic-session.target" ];
      };

      usb-passthrough-applet = {
        description = "USB Passthrough Applet";
        serviceConfig = {
          Type = "simple";
          Restart = "on-failure";
          RestartSec = "5";
          ExecSearchPath = [
            "${pkgs.ghaf-usb-applet}/bin"
          ];
          ExecStart = ''
            ${lib.getExe' pkgs.ghaf-usb-applet "usb_applet"}
          '';
        };
        partOf = [ "cosmic-session.target" ];
        wantedBy = [ "cosmic-session.target" ];
      };

      # Kill cosmic-osd if it exceeds CPU usage threshold
      # TODO: remove when upstream fixes the issue
      # ref https://github.com/pop-os/cosmic-osd/issues/70
      cosmic-cpu-watchdog =
        let
          cosmic-cpu-watchdog = pkgs.writeShellApplication {
            name = "cosmic-cpu-watchdog";

            runtimeInputs = [
              pkgs.procps
              pkgs.gawk
            ];

            text = ''
              PROCESSES=("cosmic-osd")

              THRESHOLD=80
              INTERVAL=20
              COOLDOWN=60
              LAST_KILL=0

              while true; do
                  NOW=$(date +%s)

                  for PROC in "''${PROCESSES[@]}"; do
                      PID=$(pidof -s "$PROC" 2>/dev/null) || continue
                      CPU=$(ps -o %cpu= -p "$PID" 2>/dev/null | awk '{print int($1)}')
                      [[ -z "$CPU" ]] && continue

                      if (( CPU > THRESHOLD )); then
                          if (( NOW - LAST_KILL >= COOLDOWN )); then
                              echo "$(date) High CPU detected ($PROC: ''${CPU}%), killing processes..."
                              for KILL_PROC in "''${PROCESSES[@]}"; do
                                  pkill -x "$KILL_PROC" && echo "$(date) Killed $KILL_PROC"
                              done
                              LAST_KILL=$NOW
                          fi
                      fi
                  done

                  sleep "$INTERVAL"
              done
            '';
          };
        in
        {
          description = "Ghaf COSMIC CPU usage watchdog";
          serviceConfig.ExecStart = "${getExe cosmic-cpu-watchdog}";
          after = [ "cosmic-session.target" ];
          wantedBy = [ "cosmic-session.target" ];
        };

      # We use existing blueman services and create overrides for both
      blueman-applet = {
        inherit (graphicsProfileCfg.bluetooth.applet) enable;
        serviceConfig = {
          Type = "simple";
          Restart = "on-failure";
          RestartSec = "5";
        };
        partOf = [ "cosmic-session.target" ];
        wantedBy = [ "cosmic-session.target" ];
      };

      blueman-manager = {
        inherit (graphicsProfileCfg.bluetooth.applet) enable;
      };
    };

    systemd.user.targets.ghaf-session = {
      description = "Ghaf graphical session";
      bindsTo = [ "cosmic-session.target" ];
      after = [ "cosmic-session.target" ];
      wantedBy = [ "cosmic-session.target" ];
    };

    # Below we adjust the default services from desktopManager.cosmic

    # Network manager and bluetooth could be enabled if we're sure
    # net-vm and audio-vm are not used e.g. on Orin devices
    hardware.bluetooth.enable = graphicsProfileCfg.bluetooth.enable;
    networking.networkmanager.enable = graphicsProfileCfg.networkManager.enable;

    # TODO: Revisit below when https://github.com/NixOS/nixpkgs/pull/539810 is available
    services.gnome.gnome-keyring.enable = lib.mkForce false;
    services.power-profiles-daemon.enable = lib.mkForce false;
    # Fails to build in cross-compilation for Orins
    services.orca.enable = pkgs.stdenv.hostPlatform.isx86_64;
  };
}
