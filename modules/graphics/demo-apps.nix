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
    gala-app = mkProgramOption "Gala App" false;
    element-desktop = mkProgramOption "Element desktop" weston.enableDemoApplications;
    zathura = mkProgramOption "zathura" weston.enableDemoApplications;
  };

  config = lib.mkIf weston.enable {
    ghaf.graphics.weston.launchers =
      lib.optional cfg.chromium {
        path = "${pkgs.chromium}/bin/chromium --enable-features=UseOzonePlatform --ozone-platform=wayland";
        icon = "${pkgs.chromium}/share/icons/hicolor/24x24/apps/chromium.png";
      }
      ++ lib.optional cfg.element-desktop {
        path = "${pkgs.element-desktop}/bin/element-desktop --enable-features=UseOzonePlatform --ozone-platform=wayland";
        icon = "${pkgs.element-desktop}/share/icons/hicolor/24x24/apps/element.png";
      }
      ++ lib.optional cfg.gala-app {
        path = "${pkgs.gala-app}/bin/gala --enable-features=UseOzonePlatform --ozone-platform=wayland";
        icon = "${pkgs.gala-app}/gala/resources/icon-24x24.png";
      }
      ++ lib.optional cfg.zathura {
        path = "${pkgs.zathura}/bin/zathura";
        icon = "${pkgs.zathura}/share/icons/hicolor/32x32/apps/org.pwmt.zathura.png";
      };
    environment.systemPackages =
      lib.optional cfg.chromium pkgs.chromium
      ++ lib.optional cfg.element-desktop pkgs.element-desktop
      ++ lib.optional cfg.gala-app pkgs.gala-app
      ++ lib.optional cfg.zathura pkgs.zathura;
  };
}
