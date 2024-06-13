# Copyright 2024-2025 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.ghaf.security.firejail;
in {
  imports = [../../../desktop];
  ## Option to enable Firejail sandboxing
  options.ghaf.security.firejail = {
    enable = lib.mkOption {
      description = ''
        Enable Firejail sandboxing.
      '';
      type = lib.types.bool;
      default = false;
    };

    apps = {
      firefox.enable = lib.mkOption {
        description = ''
          Enable sandboxing for Firefox. Enable this option when the browser is enabled in host.
        '';
        type = lib.types.bool;
        default = false;
      };

      chromium.enable = lib.mkOption {
        description = ''
          Enable sandboxing for Chromium. Enable this option when the browser is enabled in host.
        '';
        type = lib.types.bool;
        default = false;
      };
    };
  };

  ## Enable Firejail sandboxing
  config = lib.mkIf cfg.enable {
    ghaf.graphics = lib.mkIf config.ghaf.profiles.graphics.enable {
      demo-apps = lib.mkMerge [
        (lib.mkIf cfg.apps.firefox.enable {
          firefox = lib.mkForce false;
        })
        (lib.mkIf cfg.apps.chromium.enable {
          chromium = lib.mkForce false;
        })
      ];

      launchers =
        lib.optional cfg.apps.firefox.enable {
          name = "Firefox-safe";
          path = "/run/current-system/sw/bin/firefox";
          icon = "${pkgs.icon-pack}/firefox.svg";
        }
        ++ lib.optional cfg.apps.chromium.enable {
          name = "Chromium-safe";
          path = "/run/current-system/sw/bin/chromium";
          icon = "${pkgs.icon-pack}/chromium.svg";
        };
    };

    programs.firejail = {
      enable = true;
      wrappedBinaries = {
        # Firefox profile
        firefox = lib.mkIf cfg.apps.firefox.enable {
          executable = "${lib.getBin pkgs.firefox}/bin/firefox";
          profile = "${pkgs.firejail}/etc/firejail/firefox.profile";
          extraArgs = [
            "--whitelist=/run/current-system/sw/bin/firefox"
          ];
        };

        # Chromium profile
        chromium = lib.mkIf cfg.apps.chromium.enable {
          executable = "${lib.getBin pkgs.chromium}/bin/chromium --enable-features=UseOzonePlatform --ozone-platform=wayland";
          profile = "${pkgs.firejail}/etc/firejail/chromium-browser.profile";
          extraArgs = [
            "--whitelist=/run/current-system/sw/bin/chromium"
          ];
        };
      };
    };
  };
}
