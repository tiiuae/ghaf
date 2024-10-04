# Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.ghaf.services.bluetooth;
  inherit (lib) mkIf mkEnableOption;
  bluetoothUser = "bluetooth";
in
{
  options.ghaf.services.bluetooth = {
    enable = mkEnableOption "Bluetooth configurations";
  };
  config = mkIf cfg.enable {

    # Enable bluetooth
    hardware.bluetooth = {
      enable = true;
    };

    # Setup bluetooth user and group
    users = {
      users."${bluetoothUser}" = {
        isSystemUser = true;
        group = "${bluetoothUser}";
      };
      groups."${bluetoothUser}" = { };
    };

    # Persistent storage
    ghaf = lib.optionalAttrs (lib.hasAttr "storagevm" config.ghaf) {
      storagevm.directories = [
        {
          directory = "/var/lib/bluetooth";
          user = "bluetooth";
          group = "bluetooth";
          mode = "u=rwx,g=,o=";
        }
      ];
    };

    # Uinput kernel module
    boot.kernelModules = [ "uinput" ];

    # Rfkill udev rule
    services.udev.extraRules = ''
      KERNEL=="rfkill", SUBSYSTEM=="misc", GROUP="${bluetoothUser}"
      KERNEL=="uinput", SUBSYSTEM=="misc", GROUP="${bluetoothUser}"
    '';

    # Dbus policy updates
    services.dbus.packages = [
      (pkgs.writeTextFile {
        name = "bluez-dbus-policy";
        text = ''
          <!DOCTYPE busconfig PUBLIC
            "-//freedesktop//DTD D-BUS Bus Configuration 1.0//EN"
            "http://www.freedesktop.org/standards/dbus/1.0/busconfig.dtd">
          <busconfig>
            <policy user="${bluetoothUser}">
              <allow own="org.bluez"/>
              <allow send_destination="org.bluez.*"/>
              <allow send_interface="org.bluez.*"/>
              <allow send_type="method_call"/>
              <allow send_interface="org.freedesktop.DBus.Introspectable"/>
              <allow send_interface="org.freedesktop.DBus.Properties"/>
              <allow send_interface="org.freedesktop.DBus.ObjectManager"/>
            </policy>
            <policy user="pipewire">
              <allow send_destination="org.bluez"/>
            </policy>
          </busconfig>
        '';
        destination = "/share/dbus-1/system.d/bluez.conf";
      })
    ];

    # Configure bluetooth service
    systemd.services.bluetooth.serviceConfig = {
      User = "${bluetoothUser}";
      Group = "${bluetoothUser}";
    };
  };
}
