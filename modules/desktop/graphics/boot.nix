# Copyright 2024-2025 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  config,
  lib,
  pkgs,
  ...
}:
let
  inherit (lib)
    mkDefault
    mkIf
    mkOption
    optionals
    types
    ;

  cfg = config.ghaf.graphics.boot;

  plymouth-ghaf-background = mkIf cfg.firmwareLogo.enable (
    pkgs.runCommand "plymouth-ghaf-background" { nativeBuildInputs = [ pkgs.imagemagick ]; } ''
      if [ -n "${cfg.firmwareLogo.image}" ]; then
        # bgrt theme uses spinner theme's image directory
        # so no need to adjust bgrt theme separately
        mkdir -p $out/share/plymouth/themes/spinner
        # Resize the image to a height of 200px, keeping aspect ratio
        convert "${cfg.firmwareLogo.image}" \
          -background transparent -resize x200 \
          $out/share/plymouth/themes/spinner/bgrt-fallback.png
      fi
    ''
  );
in
{
  options.ghaf.graphics.boot = {
    enable = mkOption {
      type = types.bool;
      default = false;
      description = ''
        Enables graphical boot with plymouth.
      '';
    };

    waitForService = mkOption {
      type = types.nullOr types.str;
      default = null;
      description = ''
        If set, plymouth will wait for the specified systemd service to be started before quitting.
      '';
    };

    firmwareLogo = {
      enable = mkOption {
        type = types.bool;
        default = true;
        description = ''
          Whether to override the UEFI firmware (BGRT) boot logo.
        '';
      };

      image = mkOption {
        type = types.path;
        default = "${pkgs.ghaf-artwork}/1600px-Ghaf_logo.png";
        description = ''
          Image to use in place of the UEFI firmware (BGRT) boot logo.
          Default is the Ghaf logo.
        '';
      };
    };

    logo = {
      enable = mkOption {
        type = types.bool;
        default = false;
        description = ''
          Whether to show a custom logo at the bottom of the splash screen.
          If left disabled, no logo is shown.
        '';
      };

      image = mkOption {
        type = types.path;
        default = "${pkgs.ghaf-artwork}/ghaf-logo.png";
        description = ''
          Image to use at the bottom of the splash screen.
          Default is the Ghaf logo.
        '';
      };
    };
  };

  config = mkIf cfg.enable {
    boot = {
      plymouth = {
        enable = true;
        theme = "bgrt";
        logo = if cfg.logo.enable then cfg.logo.image else "/dev/null";

        # This is a bit hacky, as we're overriding the default spinner theme
        # It would be better to create our own custom theme
        themePackages = optionals cfg.firmwareLogo.enable [ plymouth-ghaf-background ];
      };
      # Hide boot log from user completely
      kernelParams = [
        "quiet"
        "udev.log_priority=3"
      ]
      # Disables loading the UEFI logo from firmware to /sys/firmware/acpi/bgrt
      ++ optionals cfg.firmwareLogo.enable [ "bgrt_disable=1" ];
      consoleLogLevel = mkDefault 0;
      initrd.verbose = false;
    };
    systemd.services.plymouth-quit = {
      after = mkIf (cfg.waitForService != null && cfg.waitForService != "") [ cfg.waitForService ];
    };
  };
}
