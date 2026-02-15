# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.ghaf.services.wifi;
  inherit (lib) mkIf mkEnableOption;
  inherit (config.ghaf.networking) hosts;
in
{
  _file = ./wifi.nix;

  options.ghaf.services.wifi = {
    enable = mkEnableOption "Wifi configuration for the net-vm";
  };
  config = mkIf cfg.enable {
    networking = {
      networkmanager = {
        enable = true;
        wifi.powersave = true;
        unmanaged = [ hosts.${config.networking.hostName}.interfaceName ];
      };
    };

    ghaf =
      lib.optionalAttrs config.ghaf.storagevm.enable {
        storagevm.directories = [
          "/etc/NetworkManager/system-connections/"
        ];
      }
      // {
        security.audit.extraRules = [
          "-w /etc/NetworkManager/ -p wa -k networkmanager"
        ];
      };

    environment = {

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
