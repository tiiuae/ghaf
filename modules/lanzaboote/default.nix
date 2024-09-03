# Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# ghaf's integration to lanzaboote
{
  lib,
  pkgs,
  config,
  ...
}:
let
  cfg = config.ghaf.host.secureboot;
in
{
  options.ghaf.host.secureboot = {
    enable = lib.mkEnableOption "Host secureboot";
  };

  config = lib.mkIf cfg.enable {
    # To copy demo keys to /etc/secureboot directory
    environment = {
      etc.secureboot.source = ./demo-secure-boot-keys;

      systemPackages = [
        # For debugging and troubleshooting Secure Boot.
        pkgs.sbctl
      ];
    };

    # Lanzaboote currently replaces the systemd-boot module.
    # This setting is usually set to true in configuration.nix
    # generated at installation time. So we force it to false
    # for now.
    boot = {
      loader = {
        systemd-boot.enable = lib.mkForce false;
        efi.canTouchEfiVariables = lib.mkForce false;
      };

      lanzaboote = {
        enable = true;
        pkiBundle = "/etc/secureboot";
      };
    };
  };
}
