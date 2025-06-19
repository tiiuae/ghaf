# Copyright 2022-2025 TII (SSRC) and the Ghaf contributors
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
    ;

  cfg = config.ghaf.graphics.cosmic;
  graphicsProfileCfg = config.ghaf.profiles.graphics;

  ghaf-powercontrol = pkgs.ghaf-powercontrol.override { ghafConfig = config.ghaf; };

  ghaf-cosmic-config = import ./config/cosmic-config.nix {
    inherit lib pkgs;
    secctx = cfg.securityContext;
    inherit (cfg) panelApplets;
  };

  autostart = pkgs.writeShellApplication {
    name = "autostart";

    text = ''
      gtk_dirs=(gtk-3.0 gtk-4.0)
      for dir in "''${gtk_dirs[@]}"; do
        mkdir -p "$XDG_CONFIG_HOME/$dir"
        settings="$XDG_CONFIG_HOME/$dir/settings.ini"
        [ -f "$settings" ] || echo -ne "${gtk-settings}" > "$settings"
      done

      cosmic_conf="$XDG_CONFIG_HOME/cosmic/cosmic/com.system76.CosmicTk/v1"
      mkdir -p "$cosmic_conf"
      [ -f "$cosmic_conf/apply_theme_global" ] || echo -ne "true" > "$cosmic_conf/apply_theme_global"
      [ -f "$cosmic_conf/icon_theme" ] || echo -ne "\"Papirus\"" > "$cosmic_conf/icon_theme"
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
      toString (builtins.floor (300 * 0.8))

    } '${lib.optionalString graphicsProfileCfg.allowSuspend ''notify-send -a System -u normal -t 10000 -i system "Automatic suspend" "The system will suspend soon due to inactivity.";''} brightnessctl -q -s; brightnessctl -q -m | { IFS=',' read -r _ _ _ brightness _ && [ "''${brightness%\%}" -le 25 ] || brightnessctl -q set 25% ;}' resume "brightnessctl -q -r || brightnessctl -q set 100%"
    timeout ${toString 300} "loginctl lock-session" resume "brightnessctl -q -r || brightnessctl -q set 100%"
    ${lib.optionalString graphicsProfileCfg.allowSuspend ''timeout ${
      toString (builtins.floor (300 * 3))
    } "ghaf-powercontrol suspend; ghaf-powercontrol wakeup"''}
  '';

  gtk-settings = ''
    [Settings]
    gtk-application-prefer-dark-theme=1
    gtk-icon-theme-name=Papirus
    gtk-cursor-theme-name=Pop
    gtk-cursor-theme-size=24
    gtk-button-images=1
    gtk-menu-images=1
    gtk-enable-event-sounds=1
    gtk-enable-input-feedback-sounds=1
    gtk-xft-antialias=1
    gtk-xft-hinting=1
    gtk-xft-hintstyle=hintslight
    gtk-xft-rgba=rgb
  '';

in
{
  options.ghaf.graphics.cosmic = {
    enable = mkEnableOption "cosmic";

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
            default = [
              "com.system76.CosmicPanelAppButton"
              "com.system76.CosmicPanelWorkspacesButton"
            ];
          };
          center = lib.mkOption {
            description = "List of applets to show in the center of the panel.";
            type = types.listOf types.str;
            default = [
              "com.system76.CosmicAppletTime"
              "com.system76.CosmicAppletNotifications"
            ];
          };
          right = lib.mkOption {
            description = "List of applets to show on the right side of the panel.";
            type = types.listOf types.str;
            default = [
              "com.system76.CosmicAppletInputSources"
              "com.system76.CosmicAppletStatusArea"
              "com.system76.CosmicAppletTiling"
              "com.system76.CosmicAppletAudio"
              "com.system76.CosmicAppletBattery"
              "com.system76.CosmicAppletPower"
            ];
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
  };

  config = mkIf cfg.enable {
    services.desktopManager.cosmic.enable = true;
    services.displayManager.cosmic-greeter.enable = true;

    ghaf.graphics.login-manager.enable = true;
    # Override default power controls with ghaf-powercontrol
    ghaf.graphics.power-manager.enable = true;

    environment = {
      systemPackages = with pkgs; [
        papirus-icon-theme-grey
        adwaita-icon-theme
        ghaf-wallpapers
        pamixer
        (import ../launchers-pkg.nix { inherit pkgs config; })
        # Nix's evaluation order installs ghaf-cosmic-config after cosmic tools.
        # Installing it before the cosmic tools would result in its configuration being overridden
        # by the default configurations of the cosmic tools.
        # If this behavior changes in the future, overlays for the relevant cosmic packages
        # must be added to nixpkgs.overlays to enforce the desired configuration precedence.
        ghaf-cosmic-config
      ];
      sessionVariables = {
        XDG_CONFIG_HOME = "$HOME/.config";
        XDG_DATA_HOME = "$HOME/.local/share";
        XDG_STATE_HOME = "$HOME/.local/state";
        XDG_CACHE_HOME = "$HOME/.cache";
        XDG_PICTURES_DIR = "$HOME/Pictures";
        XDG_VIDEOS_DIR = "$HOME/Videos";
        XCURSOR_THEME = "Pop";
        XCURSOR_SIZE = 24;
        GSETTINGS_SCHEMA_DIR = "${pkgs.gsettings-desktop-schemas}/share/gsettings-schemas/${pkgs.gsettings-desktop-schemas.name}/glib-2.0/schemas";
        # Enable zwlr_data_control_manager_v1 protocol for COSMIC Utilities - Clipboard Manager to work
        COSMIC_DATA_CONTROL_ENABLED = 1;
        # 'info' logs are too verbose, even on debug builds
        # RUST_LOG = if config.ghaf.profiles.debug.enable then "info" else "error";
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
          #VIDEOS=Videos
          #PUBLICSHARE=Public
          #TEMPLATES=Templates
          #DESKTOP=Desktop
        '';
      }
      // lib.optionalAttrs graphicsProfileCfg.idleManagement.enable {
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
        enable = true;
        description = "Ghaf autostart";
        serviceConfig.ExecStart = "${lib.getExe autostart}";
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
            ${lib.getExe' pkgs.ghaf-audio-control "GhafAudioControlStandalone"} --pulseaudio_server=audio-vm:${toString config.ghaf.services.audio.pulseaudioTcpControlPort} --deamon_mode=true --indicator_icon_name=adjustlevels
          '';
        };
        partOf = [ "cosmic-session.target" ];
        wantedBy = [ "cosmic-session.target" ];
      };

      # Disable XDG autostart nm-applet, replace with our own service
      "app-nm\\x2dapplet@autostart" = {
        enable = false;
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
            ${lib.getExe' pkgs.networkmanagerapplet "nm-applet"} --indicator
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
        inherit (graphicsProfileCfg.idleManagement) enable;
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
          ExecStart = "${lib.getExe pkgs.swayidle} -w -C /etc/swayidle/config";
        };
        partOf = [ "cosmic-session.target" ];
        wantedBy = [ "cosmic-session.target" ];
      };
    };

    systemd.user.targets.ghaf-session = {
      enable = true;
      description = "Ghaf graphical session";
      bindsTo = [ "cosmic-session.target" ];
      after = [ "cosmic-session.target" ];
      wantedBy = [ "cosmic-session.target" ];
    };

    # Suspend on VMs is currently disabled unconditionally due to known issues
    # Ideally, these should be controlled by the allowSuspend option
    # VM suspension known issues:
    # - Suspending a VM leads to USB controllers crashing and having to be re-initialized
    # - cosmic-comp may crash on resume
    systemd.sleep.extraConfig = mkIf (!graphicsProfileCfg.allowSuspend) ''
      AllowSuspend=no
      AllowHibernation=no
      AllowHybridSleep=no
      AllowSuspendThenHibernate=no
    '';

    # Following are changes made to default COSMIC configuration done by services.desktopManager.cosmic

    # Network manager and bluetooth could be enabled if we're sure
    # net-vm and audio-vm are not used e.g. on Orin devices
    hardware.bluetooth.enable = graphicsProfileCfg.bluetooth.enable;
    networking.networkmanager.enable = graphicsProfileCfg.networkManager.enable;

    services.gvfs.enable = lib.mkForce false;
    services.avahi.enable = lib.mkForce false;
    security.rtkit.enable = lib.mkForce false;
    services.gnome.gnome-keyring.enable = lib.mkForce false;
    services.power-profiles-daemon.enable = lib.mkForce false;

    # Normally we wouldn't want pipewire running in the graphics profile,
    # but we add it here so cosmic-osd doesn't consume too much CPU
    # ref https://github.com/pop-os/cosmic-osd/issues/70
    services.pipewire = {
      enable = !graphicsProfileCfg.proxyAudio;

      # Disable audio backends
      alsa.enable = false;
      pulse.enable = !graphicsProfileCfg.proxyAudio;
      jack.enable = false;

      # Disable the session manager
      wireplumber.enable = false;
    };
    services.playerctld.enable = true;
  };
}
