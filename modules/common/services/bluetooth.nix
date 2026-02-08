# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.ghaf.services.bluetooth;
  inherit (lib)
    mkIf
    mkEnableOption
    mkOption
    types
    ;
  bluetoothUser = "bluetooth";
in
{
  _file = ./bluetooth.nix;

  options.ghaf.services.bluetooth = {
    enable = mkEnableOption "Bluetooth configurations";

    user = mkOption {
      type = types.str;
      default = bluetoothUser;
      description = "Name of the bluetooth user";
    };

    defaultName = mkOption {
      type = types.str;
      default = "Ghaf";
      description = ''
        Default Bluetooth adapter name.

        If unset, BlueZ will attempt to fetch the hostname via hostnamed DBus service.
        If hostnamed is disabled, BlueZ will fall back to "BlueZ [BlueZ version]".
      '';
    };

  };
  config = mkIf cfg.enable {

    # Enable bluetooth
    hardware.bluetooth = {
      enable = true;
      # Save battery by disabling bluetooth on boot
      powerOnBoot = false;
      # https://github.com/bluez/bluez/blob/master/src/main.conf full list of options
      settings = {
        General = {
          Name = lib.optionalAttrs (cfg.defaultName != null && cfg.defaultName != "") cfg.defaultName;
          FastConnectable = "true";
          JustWorksRepairing = "confirm";
          Privacy = "device";
          DiscoverableTimeout = "60"; # Default is 180 seconds
        };
      };
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
          mode = "0700";
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

    # Add blueman-mechanism helper
    systemd.services.blueman-mechanism = {
      enable = true;
      description = "Blueman mechanism";
      path = [ pkgs.blueman ];
      serviceConfig = {
        Type = "dbus";
        BusName = "org.blueman.Mechanism";
        Restart = "always";
        RestartSec = "1";
        ExecStart = "${pkgs.blueman}/libexec/blueman-mechanism";
      };
    };
  };
}
