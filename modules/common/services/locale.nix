# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
{
  config,
  pkgs,
  lib,
  ...
}:
let
  inherit (lib)
    mkEnableOption
    mkIf
    mkMerge
    getExe
    ;
  useGivc = config.ghaf.givc.enable;
  globalConfPath = "/var/lib/locale/.locale-env";
  cfg = config.ghaf.services.locale;

  ghafLocaleHandler = pkgs.writeShellApplication {
    name = "ghaf-locale-handler";
    text = ''
      LOCALE_FILE="/etc/locale.conf"

      forward_givc() {
        # Forward locale settings via givc
        mapfile -t locale_settings < $LOCALE_FILE
        givc-cli ${config.ghaf.givc.cliArgs} set-locale "''${locale_settings[@]}" || echo "Failed to apply locale settings: ' ''${locale_settings[*]} '"
        exit 0
      }

      set_global() {
        GLOBAL_CONF_PATH="${globalConfPath}"
        # Set the global locale config env vars
        # which will be used by the greeter, shells, etc.
        rm -f "$GLOBAL_CONF_PATH"
        touch "$GLOBAL_CONF_PATH"
        while IFS= read -r line; do
          # Skip empty lines or lines starting with #
          [[ -z "$line" || "$line" =~ ^# ]] && continue
          echo "export $line" >> "$GLOBAL_CONF_PATH"
        done < "$LOCALE_FILE"

        # Also set LANGUAGE for highest priority localization
        if [[ -n "$LANG_VALUE" ]]; then
          echo "export LANGUAGE=$LANG_VALUE" >> "$GLOBAL_CONF_PATH"
        fi
        exit 0
      }

      # Don't do anything if locale.conf not found
      [ -f $LOCALE_FILE ] || exit 0

      LANG_VALUE=$(grep '^LANG=' "$LOCALE_FILE" | cut -d= -f2-)

      if [ $# -eq 1 ]; then
        if [ "$1" = "givc" ]; then
          forward_givc
        elif [ "$1" = "global" ]; then
          set_global
        fi
      fi

      PROFILE_FILE="$HOME/.profile"
      LOCALE_ENV_FILE="$HOME/.locale-env"
      # shellcheck disable=SC2016
      SOURCE_LINE='[ -f "$HOME/.locale-env" ] && . "$HOME/.locale-env"'

      # Handle user session language setting
      # This is needed due to Nix option `i18n.defaultLocale`,
      # which overrides session var LANG no matter what.
      # Cosmic tools do localization based on env vars:
      # LANGUAGE, LC_ALL, LC_MESSAGES, and LANG, in that order
      # So here we set LANGUAGE for the user session

      [ -f "$PROFILE_FILE" ] || touch "$PROFILE_FILE"

      if ! grep -Fxq "$SOURCE_LINE" "$PROFILE_FILE" 2>/dev/null; then
          cat >> "$PROFILE_FILE" <<'EOF'

      # Load dynamic locale
      [ -f "$HOME/.locale-env" ] && . "$HOME/.locale-env"
      EOF
      fi

      if [[ -n "$LANG_VALUE" ]]; then
          cat > "$LOCALE_ENV_FILE" <<EOF
      # Auto-generated from $LOCALE_FILE
      export LANGUAGE=$LANG_VALUE
      EOF
      fi
    '';
  };
in
{
  _file = ./locale.nix;

  options.ghaf.services.locale = {
    enable = mkEnableOption "configuring locale settings imperatively.";
    propagate = mkEnableOption "propagating locale settings from the DE to host via givc-cli." // {
      default = true;
    };
    overrideGlobal =
      mkEnableOption ''
        overriding global system locale settings.

        If enabled, this will override the NixOS default `i18n.defaultLocale`
        by exporting locale settings from `/etc/locale.conf` to the common `/etc/profile`.

        This may be needed for the greeter, shells, etc. to inherit locale
        settings properly prior to starting a user session.

        The intermediate locale settings will be stored at `/var/lib/locale/.locale-env`,
        which will be imported by `/etc/profile`.
      ''
      // {
        default = true;
      };
  };

  config = mkIf cfg.enable (mkMerge [
    {
      systemd.user = {
        paths.ghaf-locale-listener = {
          description = "Ghaf Locale Listener";
          wantedBy = [ "ghaf-session.target" ];
          pathConfig.PathModified = "/etc/locale.conf";
        };
        services.ghaf-locale-listener = {
          description = "Ghaf Locale Listener";
          serviceConfig = {
            Type = "oneshot";
            ExecStart = "${getExe ghafLocaleHandler}";
          };
        };
      };

      security.polkit = {
        enable = true;
        extraConfig = ''
          // Allow users to set locale (needed for COSMIC Settings)
          polkit.addRule(function(action, subject) {
          if (action.id == "org.freedesktop.locale1.set-locale" &&
              subject.isInGroup ("users")) {
            return polkit.Result.YES;
            }
          });
        '';
      };
    }

    (mkIf (cfg.propagate && useGivc) {
      systemd.user.services.ghaf-locale-forwarder = {
        description = "Ghaf Locale Forwarder";
        serviceConfig = {
          Type = "oneshot";
          ExecStart = "${lib.getExe ghafLocaleHandler} givc";
        };
        wantedBy = [ "ghaf-locale-listener.path" ];
      };
    })

    (mkIf (cfg.overrideGlobal && config.ghaf.storagevm.enable) {
      systemd = {
        paths.ghaf-global-locale-listener = {
          description = "Ghaf Global Locale Listener";
          wantedBy = [ "graphical.target" ];
          pathConfig.PathModified = "/etc/locale.conf";
        };
        services.ghaf-global-locale-listener = {
          description = "Ghaf Global Locale Listener";
          serviceConfig = {
            Type = "oneshot";
            ExecStart = "${getExe ghafLocaleHandler} global";
          };
        };
      };

      ghaf.storagevm.directories = [
        {
          directory = dirOf globalConfPath;
          mode = "0755";
        }
      ];

      environment.extraInit = ''
        [ -f "${globalConfPath}" ] && . "${globalConfPath}"
      '';
    })
  ]);
}
