# Copyright 2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.ghaf.reference.programs.google-chrome;
in
{
  options.ghaf.reference.programs.google-chrome = {
    enable = lib.mkEnableOption "Enable Google chrome program settings";
    openInNormalExtension = lib.mkEnableOption "browser extension to open links in the normal browser";
    defaultPolicy = lib.mkOption {
      type = lib.types.attrs;
      description = ''
        Google chrome policy options. A list of available policies
        can be found in the Chrome Enterprise documentation:
        <https://cloud.google.com/docs/chrome-enterprise/policies/>
        Make sure the selected policy is supported on Linux and your browser version.
      '';
      default = {
        PromptForDownloadLocation = true;
        AlwaysOpenPdfExternally = true;
        DefaultBrowserSettingEnabled = true;
        MetricsReportingEnabled = false;
      };
      example = lib.literalExpression ''
        {
          PromptForDownloadLocation=true;
        }
      '';
    };

    extraOpts = lib.mkOption {
      type = lib.types.attrs;
      description = ''
        Extra google chrome policy options. A list of available policies
        can be found in the Chrome Enterprise documentation:
        <https://cloud.google.com/docs/chrome-enterprise/policies/>
        Make sure the selected policy is supported on Linux and your browser version.
      '';
      default = {
      };
      example = lib.literalExpression ''
        {
          "BrowserSignin" = 0;
          "SyncDisabled" = true;
          "PasswordManagerEnabled" = false;
          "SpellcheckEnabled" = true;
          "SpellcheckLanguage" = [
            "de"
            "en-US"
          ];
        }
      '';
    };

    initialPrefs = lib.mkOption {
      type = lib.types.attrs;
      description = ''
        Initial preferences for Chrome browser.
        <https://support.google.com/chrome/a/answer/187948>
        A list of commonly used preferences can be found in the Chromium Documentation for Administrators:
        <https://www.chromium.org/administrators/configuring-other-preferences/>
        A complete list of all available preferences can be found in the Chromium source code:
        <https://chromium.googlesource.com/chromium/src/%2B/HEAD/chrome/common/pref_names.h>
        Make sure the selected preference is supported on Linux.
      '';
      default = {
        homepage = "https://www.google.com";
        homepage_is_newtabpage = false;

        browser = {
          show_home_button = true;
        };

        session = {
          restore_on_startup = 4;
          startup_urls = [ "https://www.google.com/ig" ];
        };

        bookmark_bar = {
          show_on_all_tabs = true;
        };

        sync_promo = {
          show_on_first_run_allowed = false;
        };

        distribution = {
          import_bookmarks_from_file = "bookmarks.html";
          import_bookmarks = true;
          import_history = true;
          import_home_page = true;
          import_search_engine = true;
          ping_delay = 60;
          do_not_create_desktop_shortcut = true;
          do_not_create_quick_launch_shortcut = true;
          do_not_create_taskbar_shortcut = true;
          do_not_launch_chrome = true;
          do_not_register_for_update_launch = true;
          make_chrome_default = true;
          make_chrome_default_for_user = true;
          system_level = true;
          verbose_logging = true;

          browser = {
            confirm_to_quit = true;
          };
        };

        first_run_tabs = [
          "http://www.example.com"
          "http://new_tab_page"
        ];
      };
      example = lib.literalExpression ''
        {
          "distribution": {
            "import_bookmarks_from_file": "bookmarks.html",
            "do_not_create_desktop_shortcut": true,
            "do_not_create_quick_launch_shortcut": true,
            "system_level": true,
            "verbose_logging": true
          },
          "first_run_tabs": [
            "http://www.example.com",
            "http://welcome_page",
            "http://new_tab_page"
          ],
          "browser": {
            "show_home_button": true,
            "custom_chrome_frame": false
          }
        }
      '';
    };

    policyOwner = lib.mkOption {
      type = lib.types.str;
      default = "root";
      description = "Policy files owner";
    };

    policyOwnerGroup = lib.mkOption {
      type = lib.types.str;
      default = "root";
      description = "Policy files group";
    };
  };
  config = lib.mkIf cfg.enable {

    environment.etc = lib.mkMerge [
      {
        "opt/chrome/policies/managed/default.json" = {
          text = builtins.toJSON cfg.defaultPolicy;
          user = "${cfg.policyOwner}"; # Owner is proxy-user
          group = "${cfg.policyOwnerGroup}"; # Group is proxy-admin
          mode = "0664"; # Permissions: read/write for owner/group, no permissions for others
        };
        "opt/chrome/policies/managed/extra.json" = {
          text = builtins.toJSON cfg.extraOpts;
          user = "${cfg.policyOwner}"; # Owner is proxy-user
          group = "${cfg.policyOwnerGroup}"; # Group is proxy-admin
          mode = "0664"; # Permissions: read/write for owner/group, no permissions for others
        };
        "opt/chrome/initial_preferences" = lib.mkIf (cfg.initialPrefs != { }) {
          text = builtins.toJSON cfg.initialPrefs;
          user = "${cfg.policyOwner}"; # Owner is proxy-user
          group = "${cfg.policyOwnerGroup}"; # Group is proxy-admin
          mode = "0664"; # Permissions: read/write for owner/group, no permissions for others
        };
      }
      (lib.mkIf (cfg.openInNormalExtension && config.ghaf.givc.enable) {
        "opt/chrome/native-messaging-hosts/fi.ssrc.open_normal.json" = {
          source = "${pkgs.open-normal-extension}/fi.ssrc.open_normal.json";
        };

        "open-normal-extension.cfg" = {
          text = ''
            export GIVC_PATH="${pkgs.givc-cli}"
            export GIVC_OPTS="${config.ghaf.givc.cliArgs}"
          '';
        };
      })
    ];
  };
}
