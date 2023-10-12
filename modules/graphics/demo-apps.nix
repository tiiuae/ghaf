# Copyright 2022-2023 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  pkgs,
  lib,
  config,
  ...
}: let
  cfg = config.ghaf.graphics.demo-apps;
  weston = config.ghaf.graphics.weston;

  /*
  Scaled down firefox icon
  */
  firefox-icon = pkgs.runCommand "firefox-icon-24x24" {} ''
    mkdir -p $out/share/icons/hicolor/24x24/apps
    ${pkgs.buildPackages.imagemagick}/bin/convert \
      ${pkgs.firefox}/share/icons/hicolor/128x128/apps/firefox.png \
      -resize 24x24 \
      $out/share/icons/hicolor/24x24/apps/firefox.png
  '';

  /*
  Generate launchers to be used in weston.ini

  Type: mkProgramOption ::  string -> bool -> option

  */
  mkProgramOption = name: default:
    with lib;
      mkOption {
        inherit default;
        type = types.bool;
        description = "Include package ${name} to menu and system environment";
      };
in {
  options.ghaf.graphics.demo-apps = with lib; {
    chromium = mkProgramOption "Chromium browser" false;
    firefox = mkProgramOption "Firefox browser" weston.enableDemoApplications;
    gala-app = mkProgramOption "Gala App" false;
    element-desktop = mkProgramOption "Element desktop" weston.enableDemoApplications;
    zathura = mkProgramOption "zathura" weston.enableDemoApplications;
  };

  config = lib.mkIf weston.enable {
    ghaf.graphics.weston.launchers =
      lib.optional cfg.chromium {
        name = "chromium";
        path = "${pkgs.chromium}/bin/chromium --enable-features=UseOzonePlatform --ozone-platform=wayland";
        icon = "${pkgs.chromium}/share/icons/hicolor/24x24/apps/chromium.png";
      }
      ++ lib.optional cfg.firefox {
        name = "firefox";
        path = "${pkgs.firefox}/bin/firefox";
        icon = "${firefox-icon}/share/icons/hicolor/24x24/apps/firefox.png";
      }
      ++ lib.optional cfg.element-desktop {
        name = "element";
        path = "${pkgs.element-desktop}/bin/element-desktop --enable-features=UseOzonePlatform --ozone-platform=wayland";
        icon = "${pkgs.element-desktop}/share/icons/hicolor/24x24/apps/element.png";
      }
      ++ lib.optional cfg.gala-app {
        name = "gala";
        path = "${pkgs.gala-app}/bin/gala --enable-features=UseOzonePlatform --ozone-platform=wayland";
        icon = "${pkgs.gala-app}/gala/resources/icon-24x24.png";
      }
      ++ lib.optional cfg.zathura {
        name = "zathura";
        path = "${pkgs.zathura}/bin/zathura";
        icon = "${pkgs.zathura}/share/icons/hicolor/32x32/apps/org.pwmt.zathura.png";
      };
    environment.systemPackages =
      lib.optional cfg.chromium pkgs.chromium
      ++ lib.optional cfg.element-desktop pkgs.element-desktop
      ++ lib.optional cfg.firefox pkgs.firefox
      ++ lib.optional cfg.gala-app pkgs.gala-app
      ++ lib.optional cfg.zathura pkgs.zathura;
  };
}
