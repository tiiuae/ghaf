# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  pkgs,
  lib,
  config,
  ...
}:
let
  cfg = config.ghaf.reference.host-demo-apps.demo-apps;

  /*
    Generate launchers to be used in the application drawer

    Type: mkProgramOption ::  string -> bool -> option
  */
  mkProgramOption =
    name: default:
    lib.mkOption {
      inherit default;
      type = lib.types.bool;
      description = "Include package ${name} to menu and system environment";
    };
in
{
  _file = ./demo-apps.nix;

  options.ghaf.reference.host-demo-apps.demo-apps = {
    enableDemoApplications = lib.mkEnableOption "some applications for demoing";
    chromium = mkProgramOption "Chromium browser" false;
    google-chrome = mkProgramOption "Google Chrome browser" false;
    #TODO: tmp disable firefox as 133 is not working in cross-compilation
    firefox = mkProgramOption "Firefox browser" false; # config.ghaf.graphics.enableDemoApplications;
    gala = mkProgramOption "Gala App" false;
    element-desktop = mkProgramOption "Element desktop" false; # config.ghaf.reference.host-demo-apps.demo-apps.enableDemoApplications;
    zathura = mkProgramOption "zathura" config.ghaf.reference.host-demo-apps.demo-apps.enableDemoApplications;
  };

  config = lib.mkIf config.ghaf.profiles.graphics.enable {
    ghaf.graphics.launchers =
      lib.optional cfg.google-chrome {
        name = "google-chrome";
        desktopName = "Google Chrome";
        categories = [ "WebBrowser" ];
        description = "Web Browser";
        exec = "${pkgs.google-chrome}/bin/google-chrome-stable --enable-features=UseOzonePlatform --ozone-platform=wayland";
        icon = "google-chrome";
      }
      ++ lib.optional cfg.chromium {
        name = "chromium-browser";
        desktopName = "Chromium";
        categories = [ "WebBrowser" ];
        description = "Web Browser";
        exec = "${pkgs.chromium}/bin/chromium --enable-features=UseOzonePlatform --ozone-platform=wayland";
        icon = "chromium";
      }
      ++ lib.optional cfg.firefox {
        name = "Firefox";
        desktopName = "Firefox";
        categories = [ "WebBrowser" ];
        description = "Web Browser";
        exec = "${pkgs.firefox}/bin/firefox";
        icon = "firefox";
      }
      ++ lib.optional cfg.element-desktop {
        name = "electron";
        desktopName = "Element";
        categories = [
          "InstantMessaging"
          "Chat"
        ];
        description = "General Messaging Application";
        exec = "${pkgs.element-desktop}/bin/element-desktop --enable-features=UseOzonePlatform --ozone-platform=wayland";
        icon = "element-desktop";
      }
      ++ lib.optional cfg.gala {
        name = "chrome-gala.atrc.azure-atrc.androidinthecloud.net__-Default";
        desktopName = "GALA";
        description = "Secure Android-in-the-Cloud";
        exec = "${pkgs.gala}/bin/gala --enable-features=UseOzonePlatform --ozone-platform=wayland";
        icon = "distributor-logo-android";
      }
      ++ lib.optional cfg.zathura {
        name = "org.pwmt.zathura";
        desktopName = "PDF Viewer";
        categories = [
          "Office"
          "Viewer"
        ];
        description = "PDF Viewer Application";
        exec = "${pkgs.zathura}/bin/zathura";
        icon = "document-viewer";
      };
  };
}
