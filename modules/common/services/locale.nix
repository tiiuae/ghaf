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
    getExe'
    escapeShellArg
    ;
  useGivc = config.ghaf.givc.enable;
  useStorageVm = config.ghaf.storagevm.enable;
  localeConf = "/etc/locale.conf";
  globalConfPath = "/var/lib/locale/.locale-env";
  cfg = config.ghaf.services.locale;

  ghafLocaleHandler = pkgs.writeShellApplication {
    name = "ghaf-locale-handler";
    runtimeInputs = with pkgs; [
      gawk
      givc-cli
      systemd
    ];
    text = ''
      LOCALE_FILE=${escapeShellArg localeConf}
      GLOBAL_CONF_PATH="${escapeShellArg globalConfPath}"

      forward_givc() {
        # Forward locale settings via givc
        mapfile -t locale_settings < "$LOCALE_FILE"
        givc-cli ${config.ghaf.givc.cliArgs} set-locale "''${locale_settings[@]}" \
          || echo "Failed to apply locale settings: ' ''${locale_settings[*]} '"
        exit 0
      }

      # Set the global locale config env vars
      # which will be used by the greeter, shells, etc.
      set_global() {
        awk 'NF && $0 !~ /^#/ { print "export " $0 }' "$LOCALE_FILE" > "$GLOBAL_CONF_PATH"

        # Also set LANGUAGE for highest priority localization
        if [ -n "$LANG_VALUE" ]; then
            echo "export LANGUAGE=$LANG_VALUE" >> "$GLOBAL_CONF_PATH"
        fi
      }

      monitor() {
        # Create target file in case it doesn't exist
        touch "$GLOBAL_CONF_PATH"

        if [ -s "$GLOBAL_CONF_PATH" ]; then
            # Read non-empty lines, strip "export " prefix
            mapfile -t boot_locale < <(grep -v '^\s*$' "$GLOBAL_CONF_PATH" | sed -E 's/^export\s+//')

            # Set initial locale settings
            localectl set-locale "''${boot_locale[@]}"
            echo "Initialized locale settings from existing config"
        fi
        # Safe to start monitoring
        ${getExe' pkgs.systemd "busctl"} monitor org.freedesktop.locale1 --system \
          | while read -r line; do
              if echo "$line" | grep -q "PropertiesChanged"; then
                echo "Locale change detected, updating persistent config"
                set_global
              fi
            done
        exit 0
      }

      # Don't do anything if locale.conf not found
      [ -f "$LOCALE_FILE" ] || exit 0

      LANG_VALUE=$(grep '^LANG=' "$LOCALE_FILE" | cut -d= -f2-)

      if [ $# -eq 1 ]; then
        case "$1" in
          givc) forward_givc ;;
          monitor) monitor ;;
        esac
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

      # Avoid duplicating source line
      grep -Fq "$SOURCE_LINE" "$PROFILE_FILE" || {
        cat >> "$PROFILE_FILE" <<'EOF'

      # Load dynamic locale
      [ -f "$HOME/.locale-env" ] && . "$HOME/.locale-env"
      EOF
      }

      # Write user locale env file
      if [[ -n "$LANG_VALUE" ]]; then
          cat > "$LOCALE_ENV_FILE" <<EOF
      # Auto-generated from "$LOCALE_FILE"
      export LANGUAGE=$LANG_VALUE
      EOF
      fi
    '';
  };
in
{
  _file = ./locale.nix;

  options.ghaf.services.locale = {
    enable = mkEnableOption ''
      runtime management of user and system locale settings.

      When enabled, locale values can be changed imperatively
      without rebuilding the system configuration.
    '';
    propagate = mkEnableOption ''
      propagating runtime timezone changes from the system
      to the host using `givc`.

      This keeps the host locale in sync with user-selected
      desktop locale settings.
    '';
    overrideSystemLocale = mkEnableOption ''
      overriding the system-wide locale defined by `i18n.defaultLocale`
      with runtime locale settings.

      When enabled, values from `/etc/locale.conf` are exported
      into `/etc/profile` so that early services (e.g. greeter,
      login shells) inherit the updated locale before a user
      session starts.

      Runtime locale variables are stored in
      `/var/lib/locale/.locale-env` and sourced by `/etc/profile`.
    '';
  };

  config = mkIf cfg.enable (mkMerge [
    {
      assertions = [
        {
          assertion = useStorageVm;
          message = "Runtime locale management requires the Storage VM to be enabled in the system.";
        }
        {
          assertion = cfg.propagate -> useGivc;
          message = "Enabling locale settings propagation ('ghaf.services.locale.propagate') requires GIVC to be enabled in the system.";
        }
      ];

      ghaf.storagevm.directories = [
        {
          directory = dirOf globalConfPath;
          mode = "0755";
        }
      ];

      systemd = {
        user = {
          paths.ghaf-locale-listener = {
            description = "Ghaf Locale Listener";
            wantedBy = [ "ghaf-session.target" ];
            pathConfig = {
              PathModified = globalConfPath;
              Unit = "ghaf-locale-handler.service";
            };
          };
          services.ghaf-locale-handler = {
            description = "Ghaf Locale Handler";
            serviceConfig = {
              Type = "oneshot";
              ExecStart = "${getExe ghafLocaleHandler}";
            };
          };
        };
        services.locale1-monitor = {
          description = "Locale1 D-Bus Properties Monitor";
          wantedBy = [ "multi-user.target" ];
          after = [
            "dbus.service"
            "systemd-localed.service"
          ];
          serviceConfig = {
            Type = "simple";
            ExecStart = "${getExe ghafLocaleHandler} monitor";
          };
        };
      };
    }

    (mkIf cfg.propagate {
      systemd.user.services.ghaf-locale-forwarder = {
        description = "Ghaf Locale Forwarder";
        serviceConfig = {
          Type = "oneshot";
          ExecStart = "${getExe ghafLocaleHandler} givc";
        };
        wantedBy = [ "ghaf-locale-listener.path" ];
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
    })

    (mkIf cfg.overrideSystemLocale {
      environment.extraInit = ''
        [ -f "${globalConfPath}" ] && . "${globalConfPath}"
      '';
    })
  ]);
}
