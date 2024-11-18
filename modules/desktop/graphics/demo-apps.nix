# Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  pkgs,
  lib,
  config,
  ...
}:
let
  cfg = config.ghaf.graphics.demo-apps;

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
  options.ghaf.graphics.demo-apps = {
    chromium = mkProgramOption "Chromium browser" false;
    google-chrome = mkProgramOption "Google Chrome browser" false;
    firefox = mkProgramOption "Firefox browser" config.ghaf.graphics.enableDemoApplications;
    gala-app = mkProgramOption "Gala App" false;
    element-desktop = mkProgramOption "Element desktop" config.ghaf.graphics.enableDemoApplications;
    zathura = mkProgramOption "zathura" config.ghaf.graphics.enableDemoApplications;
  };

  config = lib.mkIf config.ghaf.profiles.graphics.enable {
    ghaf.graphics.launchers =
      lib.optional cfg.google-chrome {
        name = "Google Chrome";
        description = "Web Browser";
        path = "${pkgs.google-chrome}/bin/google-chrome-stable --enable-features=UseOzonePlatform --ozone-platform=wayland";
        icon = "google-chrome";
      }
      ++ lib.optional cfg.chromium {
        name = "Chromium";
        description = "Web Browser";
        path = "${pkgs.chromium}/bin/chromium --enable-features=UseOzonePlatform --ozone-platform=wayland";
        icon = "chromium";
      }
      ++ lib.optional cfg.firefox {
        name = "Firefox";
        description = "Web Browser";
        path = "${pkgs.firefox}/bin/firefox";
        icon = "firefox";
      }
      ++ lib.optional cfg.element-desktop {
        name = "Element";
        description = "General Messaging Application";
        path = "${pkgs.element-desktop}/bin/element-desktop --enable-features=UseOzonePlatform --ozone-platform=wayland";
        icon = "element-desktop";
      }
      ++ lib.optional cfg.gala-app {
        name = "GALA";
        description = "Secure Android-in-the-Cloud";
        path = "${pkgs.gala-app}/bin/gala --enable-features=UseOzonePlatform --ozone-platform=wayland";
        icon = "distributor-logo-android";
      }
      ++ lib.optional cfg.zathura {
        name = "PDF Viewer";
        description = "PDF Viewer Application";
        path = "${pkgs.zathura}/bin/zathura";
        icon = "document-viewer";
      };
  };
}
