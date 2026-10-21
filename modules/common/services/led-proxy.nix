# SPDX-FileCopyrightText: 2022-2026 TII (CRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  config,
  lib,
  pkgs,
  ...
}:
let
  inherit (lib) mkIf;

  cfg = config.ghaf.services.led-proxy;
  unsupportedClientLeds = lib.filter (led: !(lib.elem led cfg.host.leds)) cfg.client.leds;
in
{
  _file = ./led-proxy.nix;

  options.ghaf.services.led-proxy = {
    enable = lib.mkEnableOption "sharing of host LEDs with VMs";
    client = {
      enable = lib.mkEnableOption "control of host LEDs from this VM";
      leds = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        description = "Host LEDs this VM may control. Each must also be listed in host.leds";
        default = [ ];
      };
    };
    host = {
      enable = lib.mkEnableOption "serving this host's LEDs to VMs";
      leds = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        # fix to multiline
        description = "
        Host LEDs that VMs may control, matched by name suffix (kbd_backlight matches tpacpi::kbd_backlight).
        Names with no matching LED are ignored.
        ";
        default = [
          "kbd_backlight"
          "micmute"
          "mute"
        ];
      };
    };
  };

  config =
    mkIf
      (
        cfg.enable
        # led proxy runs only on x86_64
        && pkgs.stdenv.hostPlatform.isx86_64
      )
      (
        lib.mkMerge [
          (lib.mkIf cfg.host.enable {
            boot.kernelModules = [ "leds" ];
            systemd.services = {
              "led-proxy-server" = {
                description = "LED proxy service";
                wantedBy = [ "basic.target" ];
                after = [ "basic.target" ];
                serviceConfig = {
                  Type = "simple";
                  Restart = "always";
                  RestartSec = 2;
                  ExecStart =
                    "${lib.getExe' pkgs.led-proxy "led-proxy-server"}"
                    + " "
                    + "${lib.concatStringsSep " " (map (led: "*${led}") cfg.host.leds)}";
                };
              };
            };
          })
          (lib.mkIf cfg.client.enable {
            systemd.services = {
              "led-proxy-client" = {
                description = "LED client service";
                wantedBy = [ "multi-user.target" ];
                after = [ "network.target" ];
                serviceConfig = {
                  ExecStartPre = "${lib.getExe' pkgs.kmod "modprobe"} uleds";
                  ExecStart = "${lib.getExe' pkgs.led-proxy "led-proxy-client"} ${lib.concatStringsSep " " cfg.client.leds}";
                  Restart = "on-failure";
                };
              };
            };
          })
          {
            assertions = [
              {
                assertion = unsupportedClientLeds == [ ];
                message = "
                  LED proxy client contains LEDs not supported by the host:
                  ${lib.concatStringsSep ", " unsupportedClientLeds}
                ";
              }
            ];
          }
        ]
      );
}
