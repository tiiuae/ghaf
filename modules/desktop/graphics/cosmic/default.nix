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
    getExe'
    literalExpression
    ;

  cfg = config.ghaf.graphics.cosmic;
  graphicsProfileCfg = config.ghaf.profiles.graphics;

  ghaf-powercontrol = pkgs.ghaf-powercontrol.override { ghafConfig = config.ghaf; };

  ghaf-cosmic-config = import ./config/cosmic-config.nix {
    inherit lib pkgs;
    inherit (cfg) panelApplets;
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

    text = '''' + cfg.extraAutostart;
  };

  cosmic-cpu-watchdog = pkgs.writeShellApplication {
    name = "cosmic-cpu-watchdog";

    runtimeInputs = [
      pkgs.procps
      pkgs.gawk
    ];

    text = ''
      PROCESSES=("cosmic-applet-audio" "cosmic-osd")
      KILLABLES=("cosmic-panel" "cosmic-osd")

      THRESHOLD=80
      TIMEOUT=300
      INTERVAL=10
      ELAPSED=0

      while (( ELAPSED < TIMEOUT )); do
          for PROC in "''${PROCESSES[@]}"; do
              PID=$(pgrep -n -f "$PROC" 2>/dev/null) || continue
              CPU=$(ps -o %cpu= -p "$PID" 2>/dev/null | awk '{print int($1)}')
              [[ -z "$CPU" ]] && continue

              if (( CPU > THRESHOLD )); then
                  echo "High CPU detected, killing processes..."
                  for KILL_PROC in "''${KILLABLES[@]}"; do
                      pkill -xf "$KILL_PROC" && echo "Killed $KILL_PROC"
                  done
                  exit 0
              fi
          done

          sleep "$INTERVAL"
          ELAPSED=$((ELAPSED + INTERVAL))
      done

      echo "No processes exceeded threshold, exiting"
    '';
  };

  # Change papirus folder icons to grey
  papirus-icon-theme-grey = pkgs.papirus-icon-theme.override {
    color = "grey";
    # The following fixes a cross-compilation issue
    inherit (pkgs.buildPackages) papirus-folders;
  };

  swayidleConfig = ''
    timeout ${
      toString (builtins.floor (cfg.idleManagement.duration * 0.8))

    } '${lib.optionalString graphicsProfileCfg.allowSuspend ''notify-send -a System -u normal -t 10000 -i system "Automatic suspend" "The system will suspend soon due to inactivity.";''} brightnessctl -q -s; brightnessctl -q -m | { IFS=',' read -r _ _ _ brightness _ && [ "''${brightness%\%}" -le 25 ] || brightnessctl -q set 25% ;}' resume "brightnessctl -q -r || brightnessctl -q set 100%"
    timeout ${toString cfg.idleManagement.duration} "loginctl lock-session" resume "brightnessctl -q -r || brightnessctl -q set 100%"
    ${lib.optionalString graphicsProfileCfg.allowSuspend ''timeout ${
      toString (builtins.floor (cfg.idleManagement.duration * 3))
    } "systemctl suspend"''}
  '';
in
{
  options.ghaf.graphics.cosmic = {
    enable = mkEnableOption "the COSMIC desktop environment in Ghaf";

    idleManagement = {
      enable = mkOption {
        type = types.bool;
        default = graphicsProfileCfg.idleManagement.enable;
        defaultText = literalExpression "config.ghaf.profiles.graphics.idleManagement.enable";
        description = ''
          Wether to override cosmic-idle system idle management using swayidle.

          When enabled, swayidle will handle automatic screen dimming, locking, and suspending.
        '';
      };
      duration = mkOption {
        type = types.int;
        default = 300;
        description = ''
          Timeout for idle suspension in seconds.
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

    panelApplets = mkOption {
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
          "com.system76.CosmicAppletTiling"
          "com.system76.CosmicAppletAudio"
          "com.system76.CosmicAppletBattery"
          "com.system76.CosmicAppletPower"
        ];
      };
      description = "Cosmic panel applets configuration";
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
    services.desktopManager.cosmic.enable = true;
    services.displayManager.cosmic-greeter.enable = true;

    ghaf.graphics.login-manager.enable = true;
    ghaf.graphics.login-manager.failLock.enable = true;

    ghaf.graphics.screen-recorder.enable = cfg.screenRecorder.enable;

    environment = {
      systemPackages =
        with pkgs;
        [
          papirus-icon-theme-grey
          adwaita-icon-theme
          ghaf-wallpapers
          pamixer
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
      }
      // lib.optionalAttrs graphicsProfileCfg.proxyAudio {
        PULSE_SERVER = "audio-vm:${toString config.ghaf.services.audio.pulseaudioTcpControlPort}";
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
      }
      // lib.optionalAttrs cfg.idleManagement.enable {
        "swayidle/config".text = swayidleConfig;
      }
      // lib.optionalAttrs (!graphicsProfileCfg.proxyAudio) {
        # This ensures pulse doesn't try to load any hardware modules,
        # and runs 'empty' modules instead.
        # ref https://github.com/pop-os/cosmic-osd/issues/70
        "pulse/default.pa".text = ''
          # Load a null sink so the daemon doesn't quit
          load-module module-null-sink sink_name=dummy
          # Optionally: Load a null source too
          load-module module-null-source source_name=void

          # Don't load any real hardware modules
          # You could also add: .nofail to skip errors

          # No auto-detection
          .nofail
        '';
      };
    };

    systemd.user.services = {
      autostart = {
        description = "Ghaf autostart";
        serviceConfig.ExecStart = "${getExe autostart}";
        partOf = [ "cosmic-session.target" ];
        wantedBy = [ "cosmic-session.target" ];
      };

      audio-control = {
        enable = graphicsProfileCfg.proxyAudio;
        description = "Audio Control application";
        serviceConfig = {
          Type = "simple";
          Restart = "always";
          RestartSec = "5";
          ExecStart = ''
            ${getExe' pkgs.ghaf-audio-control "GhafAudioControlStandalone"} --pulseaudio_server=audio-vm:${toString config.ghaf.services.audio.pulseaudioTcpControlPort} --deamon_mode=true --indicator_icon_name=adjustlevels
          '';
        };
        partOf = [ "cosmic-session.target" ];
        wantedBy = [ "cosmic-session.target" ];
      };
      usb-passthrough-applet = {
        description = "USB Passthrough Applet";
        serviceConfig = {
          Type = "simple";
          Restart = "always";
          RestartSec = "2";
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

      nm-applet = {
        inherit (graphicsProfileCfg.networkManager.applet) enable;
        description = "Network Manager Applet";
        serviceConfig = {
          Type = "simple";
          Restart = "always";
          RestartSec = "1";
          Environment = mkIf graphicsProfileCfg.networkManager.applet.useDbusProxy "DBUS_SYSTEM_BUS_ADDRESS=unix:path=/tmp/dbusproxy_net.sock";
          ExecStart = ''
            ${getExe' pkgs.networkmanagerapplet "nm-applet"} --indicator
          '';
        };
        partOf = [ "cosmic-session.target" ];
        wantedBy = [ "cosmic-session.target" ];
      };

      # We use existing blueman services and create overrides for both
      blueman-applet = {
        inherit (graphicsProfileCfg.bluetooth.applet) enable;
        serviceConfig = {
          Type = "simple";
          Restart = "always";
          RestartSec = "1";
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

      swayidle = {
        inherit (cfg.idleManagement) enable;
        description = "Ghaf system idle handler";
        path = with pkgs; [
          brightnessctl
          systemd
          ghaf-powercontrol
          libnotify
          wlopm
        ];
        serviceConfig = {
          Type = "simple";
          ExecStart = "${getExe pkgs.swayidle} -w -C /etc/swayidle/config";
        };
        partOf = [ "cosmic-session.target" ];
        wantedBy = [ "cosmic-session.target" ];
      };

      # Kill cosmic-osd and cosmic-applet-audio if they exceed CPU usage threshold
      # TODO: remove when upstream fixes the issue
      # ref https://github.com/pop-os/cosmic-osd/issues/70
      cosmic-cpu-watchdog = {
        description = "Ghaf COSMIC CPU usage watchdog";
        serviceConfig = {
          Type = "oneshot";
          ExecStart = "${getExe cosmic-cpu-watchdog}";
        };
        after = [ "cosmic-session.target" ];
        wantedBy = [ "cosmic-session.target" ];
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
    services.avahi.enable = lib.mkForce false;
    services.gnome.gnome-keyring.enable = lib.mkForce false;
    services.power-profiles-daemon.enable = lib.mkForce false;
    # Fails to build in cross-compilation for Orins
    services.orca.enable = pkgs.stdenv.hostPlatform.isx86_64;

    services.pipewire = {
      enable = true;

      # Disable audio backends
      alsa.enable = false;
      pulse.enable = !graphicsProfileCfg.proxyAudio;
      jack.enable = false;
    };
  };
}
