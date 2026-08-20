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

    powerOnBoot = mkOption {
      type = types.bool;
      default = false;
      description = ''
        Automatically power on Bluetooth adapters when they appear.

        This also applies when an adapter is reattached after suspend or a
        hardware kill-switch cycle.
      '';
    };

  };
  config = mkIf cfg.enable {

    # Enable bluetooth
    hardware.bluetooth = {
      enable = true;
      inherit (cfg) powerOnBoot;
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
    ghaf.storagevm.directories = lib.mkIf config.ghaf.storagevm.enable [
      {
        directory = "/var/lib/bluetooth";
        user = "bluetooth";
        group = "bluetooth";
        mode = "0700";
      }
    ];

    # Uinput kernel module
    boot.kernelModules = [
      "uinput"
      "uhid"
    ];

    # Rfkill udev rule
    services.udev.extraRules = ''
      KERNEL=="rfkill", SUBSYSTEM=="misc", GROUP="${bluetoothUser}"
      KERNEL=="uinput", SUBSYSTEM=="misc", GROUP="${bluetoothUser}"
      KERNEL=="uhid", GROUP="${bluetoothUser}" MODE="0660"
    ''
    + lib.optionalString cfg.powerOnBoot ''
      ACTION=="add", SUBSYSTEM=="bluetooth", KERNEL=="hci[0-9]*", TAG+="systemd", ENV{SYSTEMD_WANTS}+="bluetooth-power-on.service"
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

    # BlueZ AutoEnable is not sufficient when a passthrough adapter is
    # detached and reattached while bluetoothd is being restarted. Explicitly
    # restore the powered state after both service restarts and adapter
    # reappearance.
    systemd.services.bluetooth-power-on = mkIf cfg.powerOnBoot {
      description = "Power on Bluetooth adapters";
      wantedBy = [
        "bluetooth.service"
        "bluetooth.target"
      ];
      after = [ "bluetooth.service" ];
      requires = [ "bluetooth.service" ];
      partOf = [
        "bluetooth.service"
        "bluetooth.target"
      ];
      path = [
        pkgs.bluez
        pkgs.gawk
      ];
      script = ''
        controllers=()
        while IFS= read -r controller; do
          controllers+=("$controller")
        done < <(bluetoothctl list | awk '$1 == "Controller" { print $2 }')

        # Passthrough adapters normally appear after bluetoothd. Their udev add
        # event starts this unit again, so an empty controller list is not an
        # error and must not delay or fail AudioVM boot.
        if [ "''${#controllers[@]}" -eq 0 ]; then
          echo "No Bluetooth adapter is currently available"
          exit 0
        fi

        failed=false
        for controller in "''${controllers[@]}"; do
          powered=false
          for _ in $(seq 1 30); do
            if bluetoothctl show "$controller" | grep -q "Powered: yes"; then
              powered=true
              break
            fi
            bluetoothctl select "$controller" >/dev/null || true
            bluetoothctl power on || true
            sleep 1
          done

          if ! "$powered"; then
            echo "Failed to power on Bluetooth adapter $controller" >&2
            failed=true
          fi
        done

        if "$failed"; then
          exit 1
        fi
      '';
      serviceConfig = {
        Type = "oneshot";
      };
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
