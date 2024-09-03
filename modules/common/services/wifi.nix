# Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.ghaf.services.wifi;
  inherit (lib) mkIf mkForce mkEnableOption;
in
{
  options.ghaf.services.wifi = {
    enable = mkEnableOption "Wifi configuration for the net-vm";
  };
  config = mkIf cfg.enable {
    networking = {
      # wireless is disabled because we use NetworkManager for wireless
      wireless.enable = mkForce false;
      networkmanager = {
        enable = true;
        unmanaged = [ "ethint0" ];
      };
    };

    environment = {
      # noXlibs=false; needed for NetworkManager stuff
      noXlibs = false;

      etc."NetworkManager/system-connections/Wifi-1.nmconnection" = {
        text = ''
          [connection]
          id=Wifi-1
          uuid=33679db6-4cde-11ee-be56-0242ac120002
          type=wifi
          [wifi]
          mode=infrastructure
          ssid=SSID_OF_NETWORK
          [wifi-security]
          key-mgmt=wpa-psk
          psk=WPA_PASSWORD
          [ipv4]
          method=auto
          [ipv6]
          method=disabled
          [proxy]
        '';
        mode = "0600";
      };
      systemPackages = mkIf config.ghaf.profiles.debug.enable [ pkgs.tcpdump ];
    };
  };
}
