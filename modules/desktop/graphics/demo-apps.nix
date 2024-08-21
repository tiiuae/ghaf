# Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  pkgs,
  lib,
  config,
  ...
}: let
  cfg = config.ghaf.graphics.demo-apps;

  /*
    Generate launchers to be used in the application drawer

    Type: mkProgramOption ::  string -> bool -> option
  */
  mkProgramOption = name: default:
    lib.mkOption {
      inherit default;
      type = lib.types.bool;
      description = "Include package ${name} to menu and system environment";
    };
in {
  options.ghaf.graphics.demo-apps = {
    chromium = mkProgramOption "Chromium browser" false;
    firefox = mkProgramOption "Firefox browser" config.ghaf.graphics.enableDemoApplications;
    gala-app = mkProgramOption "Gala App" false;
    element-desktop = mkProgramOption "Element desktop" config.ghaf.graphics.enableDemoApplications;
    zathura = mkProgramOption "zathura" config.ghaf.graphics.enableDemoApplications;
    appflowy = mkProgramOption "Appflowy" config.ghaf.graphics.enableDemoApplications;
    #ctrl-panel = mkProgramOption "Ghaf Control panel" false;
  };

  config = lib.mkIf config.ghaf.profiles.graphics.enable {
    ghaf.graphics.launchers =
      lib.optional cfg.chromium {
        name = "Chromium";
        path = "${pkgs.chromium}/bin/chromium --enable-features=UseOzonePlatform --ozone-platform=wayland";
        icon = "${pkgs.icon-pack}/chromium.svg";
      }
      ++ lib.optional cfg.firefox {
        name = "Firefox";
        path = "${pkgs.firefox}/bin/firefox";
        icon = "${pkgs.icon-pack}/firefox.svg";
      }
      ++ lib.optional cfg.element-desktop {
        name = "Element";
        path = "${pkgs.element-desktop}/bin/element-desktop --enable-features=UseOzonePlatform --ozone-platform=wayland";
        icon = "${pkgs.icon-pack}/element-desktop.svg";
      }
      ++ lib.optional cfg.gala-app {
        name = "GALA";
        path = "${pkgs.gala-app}/bin/gala --enable-features=UseOzonePlatform --ozone-platform=wayland";
        icon = "${pkgs.icon-pack}/distributor-logo-android.svg";
      }
      ++ lib.optional cfg.zathura {
        name = "PDF Viewer";
        path = "${pkgs.zathura}/bin/zathura";
        icon = "${pkgs.icon-pack}/document-viewer.svg";
      }
      ++ lib.optional (cfg.appflowy && pkgs.stdenv.isx86_64) {
        name = "AppFlowy";
        path = "${pkgs.appflowy}/bin/appflowy";
        icon = "${pkgs.appflowy}/opt/data/flutter_assets/assets/images/flowy_logo.svg";
      }
      #++ lib.optional cfg.ctrl-panel {
      #  name = "Control panel";
      #  path = "${pkgs.ctrl-panel}/bin/ctrl-panel";
      #  icon = "${pkgs.icon-pack}/utilities-tweak-tool.svg";
      #}
      ;
  };
}
