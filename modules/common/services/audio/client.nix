# SPDX-FileCopyrightText: 2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  config,
  lib,
  ...
}:
let
  cfg = config.ghaf.services.audio;
  inherit (lib)
    mkEnableOption
    mkIf
    ;

in
{
  options.ghaf.services.audio = {
    client = mkEnableOption "pipewire audio for client VMs";
  };

  config = mkIf cfg.client {
    services.avahi = {
      enable = true;
      ipv6 = false;
      nssmdns4 = true;
      openFirewall = true;
      allowInterfaces = [ "ethint0" ];
    };

    services.resolved = {
      enable = true;

      llmnr = "false";

      extraConfig = ''
        MulticastDNS=no
        DNSStubListener=yes
      '';
    };

    services.pipewire = {
      enable = true;
      # Disable audio backends
      alsa.enable = false;
      pulse.enable = true;
      jack.enable = false;
      systemWide = false;
      extraConfig = {
        pipewire-pulse."10-network-discover" = {
          "pulse.cmd" = [
            {
              cmd = "load-module";
              args = "module-zeroconf-discover";
              flags = [ "nofail" ];
            }
          ];
        };
      };
    };
  };
}
