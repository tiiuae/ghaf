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
        name = "Google Chrome";
        description = "Web Browser";
        execPath = "${pkgs.google-chrome}/bin/google-chrome-stable --enable-features=UseOzonePlatform --ozone-platform=wayland";
        icon = "google-chrome";
      }
      ++ lib.optional cfg.chromium {
        name = "Chromium";
        description = "Web Browser";
        execPath = "${pkgs.chromium}/bin/chromium --enable-features=UseOzonePlatform --ozone-platform=wayland";
        icon = "chromium";
      }
      ++ lib.optional cfg.firefox {
        name = "Firefox";
        description = "Web Browser";
        execPath = "${pkgs.firefox}/bin/firefox";
        icon = "firefox";
      }
      ++ lib.optional cfg.element-desktop {
        name = "Element";
        description = "General Messaging Application";
        execPath = "${pkgs.element-desktop}/bin/element-desktop --enable-features=UseOzonePlatform --ozone-platform=wayland";
        icon = "element-desktop";
      }
      ++ lib.optional cfg.gala {
        name = "GALA";
        description = "Secure Android-in-the-Cloud";
        execPath = "${pkgs.gala}/bin/gala --enable-features=UseOzonePlatform --ozone-platform=wayland";
        icon = "distributor-logo-android";
      }
      ++ lib.optional cfg.zathura {
        name = "PDF Viewer";
        description = "PDF Viewer Application";
        execPath = "${pkgs.zathura}/bin/zathura";
        icon = "document-viewer";
      };
  };
}
