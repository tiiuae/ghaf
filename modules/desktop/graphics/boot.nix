# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
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
    mkEnableOption
    mkIf
    mkOption
    mkForce
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

  # ShowDelay and DeviceTimeout are not exposed in nixpkgs plymouth module
  # so we have to override the config file ourselves
  # ref: https://github.com/NixOS/nixpkgs/blob/nixos-unstable/nixos/modules/system/boot/plymouth.nix
  configFile = pkgs.writeText "plymouthd.conf" ''
    [Daemon]
    ShowDelay=${toString cfg.splashDelay}
    DeviceTimeout=${toString cfg.deviceTimeout}
    Theme=${cfg.theme}
    ${config.boot.plymouth.extraConfig}
  '';
in
{
  _file = ./boot.nix;

  options.ghaf.graphics.boot = {
    enable = mkEnableOption "graphical boot with plymouth";

    waitForService = mkOption {
      type = types.nullOr types.str;
      default = null;
      description = ''
        If set, plymouth will wait for the specified systemd service to be started before quitting.
      '';
    };

    theme = mkOption {
      type = types.enum [
        "bgrt"
        "details"
        "fade-in"
        "glow"
        "script"
        "solar"
        "spinfinity"
        "spinner"
        "text"
        "tribar"
      ];
      default = "bgrt";
      description = ''
        Plymouth theme to use. The "bgrt" theme is recommended for UEFI systems.
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
      enable = mkEnableOption "custom logo at the bottom of the splash screen";

      image = mkOption {
        type = types.path;
        default = "${pkgs.ghaf-artwork}/ghaf-logo-512px.png";
        description = ''
          Image to use at the bottom of the splash screen.
          Default is the Ghaf logo.
        '';
      };
    };

    renderer = mkOption {
      type = types.enum [
        "gpu"
        "simpledrm"
      ];
      default = "simpledrm";
      description = ''
        Renderer for the graphical boot splash.

        - simpledrm: Use a simple framebuffer. Recommended if the GPU is not ready at early boot.
        - gpu: Use the system GPU if drivers are available in the initrd.
      '';
    };

    splashDelay = mkOption {
      type = types.nullOr types.int;
      default = 0;
      description = ''
        Delay in seconds before showing the splash screen.
      '';
    };

    deviceTimeout = mkOption {
      type = types.nullOr types.int;
      default = 8;
      description = ''
        Timeout in seconds to wait for the graphics device to become ready.
      '';
    };

    debug = mkEnableOption "plymouth debug logs";
  };

  config = mkIf cfg.enable {
    boot = {
      plymouth = {
        enable = true;
        inherit (cfg) theme;
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
      ++ optionals cfg.debug [ "plymouth.debug" ]
      # Disables loading the UEFI logo from firmware to /sys/firmware/acpi/bgrt
      ++ optionals cfg.firmwareLogo.enable [ "bgrt_disable=1" ]
      ++ (
        if cfg.renderer == "simpledrm" then
          [ "plymouth.use-simpledrm" ]
        else
          [
            "plymouth.use-simpledrm=0"
            "plymouth.ignore-serial-consoles"
          ]
      );
      consoleLogLevel = mkDefault 0;
      initrd.verbose = false;
    };
    systemd.services.plymouth-quit = {
      after = mkIf (cfg.waitForService != null && cfg.waitForService != "") [ cfg.waitForService ];
    };
    environment.etc."plymouth/plymouthd.conf".source = mkForce configFile;
    boot.initrd.systemd.contents."/etc/plymouth/plymouthd.conf".source = mkForce configFile;
  };
}
