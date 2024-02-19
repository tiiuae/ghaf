# Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  lib,
  pkgs,
  config,
  ...
}: let
  cfg = config.ghaf.passwordless.authentication;
in {
  options.ghaf.passwordless.authentication.enable = lib.mkOption {
    description = "Yubikeys Support";
    type = lib.types.bool;
    default = false;
  };

  config = lib.mkIf cfg.enable {
    environment.etc.u2f_mappings.source = ./demo-yubikeys/u2f_keys;
    environment.systemPackages = [
      # For generating and debugging Yubikeys
      pkgs.pam_u2f
    ];

    security.pam.services = {
      login.u2fAuth = true;
      sudo.u2fAuth = true;
      sshd.u2fAuth = true;
    };

    security.pam.u2f = {
      authFile = "/etc/u2f_mappings";
      cue = true;
      control = "sufficient";
    };
  };
}
