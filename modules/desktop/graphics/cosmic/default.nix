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
    inherit (cfg) topPanelApplets bottomPanelApplets;
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
    extraShortcuts = lib.optionals cfg.screenRecorder.enable [
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
      login-manager.failLock.enable = false;
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
          (import ../launchers-pkg.nix { inherit pkgs config; })
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

    fonts.packages = [
      pkgs.inter
    ];

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
          Path = [
            "${pkgs.ghaf-usb-applet}/bin"
          ];
          ExecStart = ''
            ${lib.getExe' pkgs.ghaf-usb-applet "usb_applet"}
          '';
        };
        partOf = [ "cosmic-session.target" ];
        wantedBy = [ "cosmic-session.target" ];
      };

      # Kill cosmic-osd and cosmic-applet-audio if they exceed CPU usage threshold
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
              INTERVAL=10
              COOLDOWN=60
              LAST_KILL=0

              while true; do
                  NOW=$(date +%s)

                  for PROC in "''${PROCESSES[@]}"; do
                      PID=$(pgrep -n -f "$PROC" 2>/dev/null) || continue
                      CPU=$(ps -o %cpu= -p "$PID" 2>/dev/null | awk '{print int($1)}')
                      [[ -z "$CPU" ]] && continue

                      if (( CPU > THRESHOLD )); then
                          if (( NOW - LAST_KILL >= COOLDOWN )); then
                              echo "$(date) High CPU detected ($PROC: ''${CPU}%), killing processes..."
                              for KILL_PROC in "''${PROCESSES[@]}"; do
                                  pkill -xf "$KILL_PROC" && echo "$(date) Killed $KILL_PROC"
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
          serviceConfig = {
            Type = "oneshot";
            ExecStart = "${getExe cosmic-cpu-watchdog}";
          };
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
          Environment = mkIf graphicsProfileCfg.bluetooth.applet.useDbusProxy "DBUS_SYSTEM_BUS_ADDRESS=unix:path=/tmp/dbusproxy_snd.sock";
        };
        partOf = [ "cosmic-session.target" ];
        wantedBy = [ "cosmic-session.target" ];
      };

      blueman-manager = {
        inherit (graphicsProfileCfg.bluetooth.applet) enable;
        serviceConfig = {
          Environment = mkIf graphicsProfileCfg.bluetooth.applet.useDbusProxy "DBUS_SYSTEM_BUS_ADDRESS=unix:path=/tmp/dbusproxy_snd.sock";
        };
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

    services.gvfs.enable = lib.mkForce false;
    services.gnome.gnome-keyring.enable = lib.mkForce false;
    services.power-profiles-daemon.enable = lib.mkForce false;
    # Fails to build in cross-compilation for Orins
    services.orca.enable = pkgs.stdenv.hostPlatform.isx86_64;
  };
}
