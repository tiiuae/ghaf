# Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  lib,
  pkgs,
  config,
  ...
}:
let
  cfg = config.ghaf.graphics.cosmic;

  inherit (import ../../../../lib/launcher.nix { inherit pkgs lib; }) rmDesktopEntries;

  ghaf-powercontrol = pkgs.ghaf-powercontrol.override { ghafConfig = config.ghaf; };

  ghaf-cosmic-config = import ./config/cosmic-config.nix {
    inherit lib pkgs;
  };

  autostart = pkgs.writeShellApplication {
    name = "autostart";

    runtimeInputs = [
      pkgs.systemd
      pkgs.dbus
      pkgs.glib
    ];

    text = ''
      mkdir -p "$XDG_CONFIG_HOME/gtk-3.0" "$XDG_CONFIG_HOME/gtk-4.0"
      [ ! -f "$XDG_CONFIG_HOME/gtk-3.0/settings.ini" ] && echo -ne "${gtk-settings}" > "$XDG_CONFIG_HOME/gtk-3.0/settings.ini"
      [ ! -f "$XDG_CONFIG_HOME/gtk-4.0/settings.ini" ] && echo -ne "${gtk-settings}" > "$XDG_CONFIG_HOME/gtk-4.0/settings.ini"
    '';
  };

  # Change papirus folder icons to grey
  papirus-icon-theme-grey = pkgs.papirus-icon-theme.override {
    color = "grey";
  };

  swayidleConfig = ''
    timeout ${
      toString (builtins.floor (300 * 0.8))
    } 'notify-send -a System -u normal -t 10000 -i system "Automatic suspend" "The system will suspend soon due to inactivity."; brightnessctl -q -s; brightnessctl -q -m | { IFS=',' read -r _ _ _ brightness _ && [ "''${brightness%\%}" -le 25 ] || brightnessctl -q set 25% ;}' resume "brightnessctl -q -r || brightnessctl -q set 100%"
    timeout ${toString 300} "loginctl lock-session" resume "brightnessctl -q -r || brightnessctl -q set 100%"
    timeout ${toString (builtins.floor (300 * 1.5))} "wlopm --off \*" resume "wlopm --on \*"
    timeout ${toString (builtins.floor (300 * 3))} "ghaf-powercontrol suspend"
    after-resume "wlopm --on \*; brightnessctl -q -r || brightnessctl -q set 100%"
    unlock "brightnessctl -q -r || brightnessctl -q set 100%"
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
    enable = lib.mkEnableOption "cosmic";
  };

  config = lib.mkIf cfg.enable {
    nixpkgs.overlays = [
      (
        _final: prev:
        let
          overrideDefaultConfigs = [
            # "cosmic-applets"
            "cosmic-applibrary"
            "cosmic-bg"
            "cosmic-comp"
            "cosmic-edit"
            "cosmic-files"
            "cosmic-icons"
            "cosmic-idle"
            "cosmic-launcher"
            "cosmic-notifications"
            "cosmic-osd"
            "cosmic-panel"
            "cosmic-player"
            "cosmic-randr"
            "cosmic-screenshot"
            # "cosmic-session"
            # "cosmic-settings"
            "cosmic-settings-daemon"
            "cosmic-term"
            "cosmic-wallpapers"
            "cosmic-workspaces-epoch"
          ];
          # Override cosmic packages' default configs with our own
          replacedConfigsPackages = builtins.listToAttrs (
            builtins.map (pkg: {
              name = pkg;
              value = prev.${pkg}.overrideAttrs (oldAttrs: {
                postFixup =
                  oldAttrs.postFixup or ""
                  + ''
                    if [ -d "$out/share/cosmic" ]; then
                      ${lib.getExe pkgs.rsync} -av --existing "${ghaf-cosmic-config}/share/cosmic/" "$out/share/cosmic/"
                    fi
                  '';
              });
            }) (builtins.filter (p: builtins.elem p overrideDefaultConfigs) (builtins.attrNames prev))
          );

          # Ghaf specific functionality overrides + default system configs
          adjustedFunctionalityPackages = {
            # Add DBUS proxy socket for audio, network, and Bluetooth applets
            cosmic-applets = prev.cosmic-applets.overrideAttrs (oldAttrs: {
              postInstall =
                oldAttrs.postInstall or ""
                + ''
                  sed -i 's|^Exec=.*|Exec=env DBUS_SYSTEM_BUS_ADDRESS=unix:path=/tmp/dbusproxy_net.sock cosmic-applet-network|' $out/share/applications/com.system76.CosmicAppletNetwork.desktop
                  sed -i 's|^Exec=.*|Exec=env PULSE_SERVER="audio-vm:${toString config.ghaf.services.audio.pulseaudioTcpControlPort}" DBUS_SYSTEM_BUS_ADDRESS=unix:path=/tmp/dbusproxy_snd.sock cosmic-applet-audio|' $out/share/applications/com.system76.CosmicAppletAudio.desktop
                  sed -i 's|^Exec=.*|Exec=env DBUS_SYSTEM_BUS_ADDRESS=unix:path=/tmp/dbusproxy_snd.sock cosmic-applet-bluetooth|' $out/share/applications/com.system76.CosmicAppletBluetooth.desktop
                '';
              postFixup =
                oldAttrs.postFixup or ""
                + ''
                  if [ -d "$out/share/cosmic" ]; then
                    ${lib.getExe pkgs.rsync} -av --existing "${ghaf-cosmic-config}/share/cosmic/" "$out/share/cosmic/"
                  fi
                '';
            });

            # Disable certain settings pages in cosmic-settings
            cosmic-settings = prev.cosmic-settings.overrideAttrs (oldAttrs: {
              cargoBuildFlags = (oldAttrs.cargoBuildFlags or [ ]) ++ [
                "--no-default-features"
                "--features"
                "a11y,dbus-config,single-instance,wgpu,page-accessibility,page-about,page-bluetooth,page-date,page-default-apps,page-input,page-networking,page-region,page-window-management,page-workspaces,xdg-portal,wayland"
              ];
              postFixup =
                oldAttrs.postFixup or ""
                + ''
                  if [ -d "$out/share/cosmic" ]; then
                    ${lib.getExe pkgs.rsync} -av --existing "${ghaf-cosmic-config}/share/cosmic/" "$out/share/cosmic/"
                  fi
                '';
            });

            # Disable network manager in cosmic-greeter
            cosmic-greeter = prev.cosmic-greeter.overrideAttrs (oldAttrs: {
              cargoBuildFlags = (oldAttrs.cargoBuildFlags or [ ]) ++ [
                "--no-default-features"
                "--features"
                "logind,upower"
              ];
              postFixup =
                oldAttrs.postFixup or ""
                + ''
                  if [ -d "$out/share/cosmic" ]; then
                    ${lib.getExe pkgs.rsync} -av --existing "${ghaf-cosmic-config}/share/cosmic/" "$out/share/cosmic/"
                  fi
                '';
            });

            # Change the cosmic-session DCONF_PROFILE var to cosmic-ghaf
            cosmic-session = prev.cosmic-session.overrideAttrs (oldAttrs: {
              justFlags = builtins.map (
                flag: if flag == "cosmic" then "cosmic-ghaf" else flag
              ) oldAttrs.justFlags;
              postFixup =
                oldAttrs.postFixup or ""
                + ''
                  if [ -d "$out/share/cosmic" ]; then
                    ${lib.getExe pkgs.rsync} -av --existing "${ghaf-cosmic-config}/share/cosmic/" "$out/share/cosmic/"
                  fi
                '';
            });
          };

        in
        replacedConfigsPackages // adjustedFunctionalityPackages
      )
    ];

    # Login is handled by cosmic-greeter
    ghaf.graphics.login-manager.enable = false;

    environment = {
      systemPackages =
        with pkgs;
        [
          papirus-icon-theme-grey
          adwaita-icon-theme
          pamixer
          ghaf-cosmic-config
          (import ../launchers-pkg.nix { inherit pkgs config; })
        ]
        ++ (rmDesktopEntries [ ]);
      sessionVariables = {
        XDG_CONFIG_HOME = "$HOME/.config";
        XDG_DATA_HOME = "$HOME/.local/share";
        XDG_STATE_HOME = "$HOME/.local/state";
        XDG_CACHE_HOME = "$HOME/.cache";
        XDG_PICTURES_DIR = "$HOME/Pictures";
        XDG_VIDEOS_DIR = "$HOME/Videos";
        PULSE_SERVER = "audio-vm:${toString config.ghaf.services.audio.pulseaudioTcpControlPort}";
        XCURSOR_THEME = "Pop";
        XCURSOR_SIZE = 24;
        GSETTINGS_SCHEMA_DIR = "${pkgs.gsettings-desktop-schemas}/share/gsettings-schemas/${pkgs.gsettings-desktop-schemas.name}/glib-2.0/schemas";
        # Enable zwlr_data_control_manager_v1 protocol for COSMIC Utilities - Clipboard Manager to work
        COSMIC_DATA_CONTROL_ENABLED = 1;
      };
      etc."xdg/user-dirs.defaults".text = ''
        #DOWNLOAD=Downloads
        #DOCUMENTS=Documents
        #MUSIC=Music
        #PICTURES=Pictures
        #VIDEOS=Videos
        #PUBLICSHARE=Public
        #TEMPLATES=Templates
        #DESKTOP=Desktop
      '';
      etc."swayidle/config".text = swayidleConfig;
    };

    # Needed for the greeter to query systemd-homed users correctly
    systemd.services.cosmic-greeter-daemon.environment.LD_LIBRARY_PATH = "${pkgs.lib.makeLibraryPath [
      pkgs.systemd
    ]}";

    security.pam.services = {
      cosmic-greeter.rules.auth = {
        systemd_home.order = 11399; # Re-order to allow either password _or_ fingerprint
        fprintd.args = [ "maxtries=3" ];
      };
      greetd = {
        fprintAuth = false; # User needs to enter password to decrypt home
        rules = {
          account.group_video = {
            enable = true;
            control = "requisite";
            modulePath = "${pkgs.linux-pam}/lib/security/pam_succeed_if.so";
            order = 10000;
            args = [
              "user"
              "ingroup"
              "video"
            ];
          };
        };
      };
    };

    services = {
      desktopManager.cosmic.enable = true;
      displayManager.cosmic-greeter.enable = true;

      greetd = {
        enable = true;
        settings.default_session =
          let
            greeter-autostart = pkgs.writeShellApplication {
              name = "greeter-autostart";
              runtimeInputs = [
                pkgs.cosmic-comp
                pkgs.cosmic-greeter
                pkgs.brightnessctl
              ];
              text = ''
                brightnessctl set 100%
                cosmic-comp cosmic-greeter
              '';
            };
          in
          {
            command = lib.mkForce ''${lib.getExe' pkgs.coreutils "env"} XCURSOR_THEME="''${XCURSOR_THEME:-Pop}" systemd-cat -t cosmic-greeter ${lib.getExe greeter-autostart}'';
          };
      };

      seatd = {
        enable = true;
        group = "video";
      };

      # Allow video group to change brightness
      udev.extraRules = ''
        ACTION=="add", SUBSYSTEM=="backlight", RUN+="${pkgs.coreutils}/bin/chgrp video $sys$devpath/brightness", RUN+="${pkgs.coreutils}/bin/chmod a+w $sys$devpath/brightness"
      '';
    };

    users.users.cosmic-greeter.extraGroups = [ "video" ];

    systemd.user.services = {
      autostart = {
        enable = true;
        description = "Ghaf autostart";
        serviceConfig.ExecStart = "${lib.getExe autostart}";
        partOf = [ "cosmic-session.target" ];
        wantedBy = [ "cosmic-session.target" ];
      };

      audio-control = {
        enable = true;
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

      # Disable XDG autostart nm-applet, replcae with our own service
      "app-nm\\x2dapplet@autostart" = {
        enable = false;
      };

      nm-applet = {
        enable = true;
        description = "Network Manager Applet";
        serviceConfig = {
          Type = "simple";
          Restart = "always";
          RestartSec = "1";
          Environment = "DBUS_SYSTEM_BUS_ADDRESS=unix:path=/tmp/dbusproxy_net.sock";
          ExecStart = ''
            ${lib.getExe' pkgs.networkmanagerapplet "nm-applet"} --indicator
          '';
        };
        partOf = [ "cosmic-session.target" ];
        wantedBy = [ "cosmic-session.target" ];
      };

      # We use existing blueman services and create overrides for both
      blueman-applet = {
        enable = true;
        serviceConfig = {
          Type = "simple";
          Restart = "always";
          RestartSec = "1";
          ExecStart = [
            ""
            "${lib.getExe pkgs.bt-launcher} applet"
          ];
        };
        partOf = [ "cosmic-session.target" ];
        wantedBy = [ "cosmic-session.target" ];
      };

      blueman-manager = {
        enable = true;
        serviceConfig.ExecStart = [
          ""
          "${lib.getExe pkgs.bt-launcher}"
        ];
      };

      swayidle = {
        enable = true;
        description = "Ghaf system idle handler";
        path = with pkgs; [
          brightnessctl
          systemd
          wlopm
          ghaf-powercontrol
          libnotify
        ];
        serviceConfig = {
          Type = "simple";
          ExecStart = "${lib.getExe pkgs.swayidle} -w -C /etc/swayidle/config";
        };
        partOf = [ "ghaf-session.target" ];
        wantedBy = [ "ghaf-session.target" ];
      };
    };

    systemd.user.targets.ghaf-session = {
      enable = true;
      description = "Ghaf graphical session";
      bindsTo = [ "cosmic-session.target" ];
      after = [ "cosmic-session.target" ];
      wantedBy = [ "cosmic-session.target" ];
    };

    # cosmic-ghaf - our own cosmic dconf profile
    programs.dconf = {
      enable = true;
      profiles.cosmic-ghaf = {
        databases = [
          {
            lockAll = false;
            settings = {
              "org/gnome/desktop/interface" = {
                color-scheme = "prefer-dark";
                cursor-theme = "Pop";
                icon-theme = "Papirus";
                clock-format = "24h";
              };
              "org/gnome/nm-applet" = {
                disable-connected-notifications = true;
                disable-disconnected-notifications = true;
              };
            };
          }
        ];
      };
    };

    # Following are changes made to default COSMIC configuration found in nixos-cosmic upstream
    hardware.bluetooth.enable = lib.mkForce false;
    # services.acpid.enable = lib.mkForce false;
    services.gvfs.enable = lib.mkForce false;
    services.avahi.enable = lib.mkForce false;
    security.rtkit.enable = lib.mkForce false;
    services.geoclue2.enable = lib.mkForce false;
    networking.networkmanager.enable = lib.mkForce false;
    services.gnome.gnome-keyring.enable = lib.mkForce false;
    # services.upower.enable = lib.mkForce false;
    services.pipewire.enable = lib.mkForce false;
    services.playerctld.enable = true;
    # Fails to replace adwaita cursor with Pop/Cosmic
    # TODO: Investigate further
    xdg.icons.fallbackCursorThemes = lib.mkDefault [
      "Pop"
      "Cosmic"
      "Adwaita"
    ];
  };
}
