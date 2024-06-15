# Copyright 2024-2025 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  config,
  lib,
  pkgs,
  ...
}:
{
  ## Apparmor profile for ping
  config.security.apparmor.policies."bin.ping" = lib.mkIf config.ghaf.security.apparmor.enable {
    profile = ''
      #include <tunables/global>
      ${pkgs.iputils}/bin/ping {
        #include <abstractions/base>
        #include <abstractions/consoles>
        #include <abstractions/nameservice>

        include "${pkgs.apparmorRulesFromClosure { name = "ping"; } [ pkgs.iputils ]}"

        capability net_raw,
        capability setuid,
        network inet raw,

        ${pkgs.iputils}/bin/ping mixr,
        /etc/modules.conf r,
      }

    '';
  };
}
