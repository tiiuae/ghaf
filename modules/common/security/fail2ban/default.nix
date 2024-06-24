# Copyright 2024-2025 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  config,
  lib,
  ...
}: let
  cfg = config.ghaf.security.fail2ban;
in {
  #imports = [../../desktop];
  ## Option to enable fail2ban sandboxing
  options.ghaf.security.fail2ban = {
    enable = lib.mkOption {
      description = ''
        Enable fail2ban.
      '';
      type = lib.types.bool;
      default = false;
    };
  };

  ## Enable fail2ban sandboxing
  config = {
    services.fail2ban = lib.mkIf cfg.enable {
      enable = true;
      bantime = "30m";
      maxretry = 3;
      bantime-increment.enable = true;
      bantime-increment.factor = "2";
      jails = {
        # TODO: define jails here
        # sshd is jailed by default
      };
    };
  };
}
