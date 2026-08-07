# SPDX-FileCopyrightText: 2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.ghaf.services.fortivpn;
  isGuiVm = config.networking.hostName == "gui-vm";
  isNetVm = config.networking.hostName == "net-vm";
  certificateDirectory = "/var/lib/ghaf/fortivpn";
  backendPackage = pkgs.networkmanager-fortisslvpn.override { withGnome = false; };
  editorPackage = pkgs.networkmanager-fortisslvpn;
  busName = "org.ghaf.FortiVpn";
  interfaceName = "org.ghaf.FortiVpn1";
  proxyUser = config.ghaf.users.proxyUser.name;
  mkDbusPolicyPackage =
    name: callerPolicy:
    pkgs.writeTextFile {
      inherit name;
      destination = "/share/dbus-1/system.d/${name}.conf";
      text = ''
        <!DOCTYPE busconfig PUBLIC
          "-//freedesktop//DTD D-BUS Bus Configuration 1.0//EN"
          "http://www.freedesktop.org/standards/dbus/1.0/busconfig.dtd">
        <busconfig>
          <policy context="default">
            <deny own="${busName}"/>
            <deny send_destination="${busName}"/>
          </policy>
          <policy user="root">
            <allow own="${busName}"/>
            <allow send_destination="${busName}"/>
          </policy>
          ${callerPolicy}
        </busconfig>
      '';
    };
  serviceHardening = import ../systemd/hardened-configs/fortivpn.nix;
in
{
  _file = ./fortivpn.nix;

  options.ghaf.services.fortivpn.enable =
    lib.mkEnableOption "Fortinet SSL VPN support in the GUI VM and Net VM";

  config = lib.mkIf cfg.enable (
    lib.mkMerge [
      {
        assertions = [
          {
            assertion = isGuiVm || isNetVm;
            message = "ghaf.services.fortivpn is supported only in gui-vm and net-vm";
          }
          {
            assertion = config.ghaf.givc.enable;
            message = "ghaf.services.fortivpn requires GIVC for GUI VM access to NetworkManager";
          }
        ];
      }

      (lib.mkIf isGuiVm {
        environment.etc."NetworkManager/${editorPackage.networkManagerPlugin}".source =
          "${editorPackage}/lib/NetworkManager/${editorPackage.networkManagerPlugin}";

        environment.systemPackages = [
          editorPackage
          pkgs.ghaf-fortivpn
          pkgs.networkmanager
          pkgs.networkmanagerapplet
        ];

        services.dbus.packages = [
          (mkDbusPolicyPackage "ghaf-fortivpn-gui" ''
            <policy group="users">
              <allow send_destination="${busName}" send_interface="${interfaceName}"/>
              <allow send_destination="${busName}" send_interface="org.freedesktop.DBus.Introspectable"/>
              <allow send_destination="${busName}" send_interface="org.freedesktop.DBus.Properties"/>
            </policy>
          '')
        ];

        systemd.services.dbus-proxy-fortivpn = {
          description = "DBus proxy for the Fortinet VPN service in net-vm";
          after = [ "givc-gui-vm.service" ];
          requires = [ "givc-gui-vm.service" ];
          wantedBy = [ "multi-user.target" ];
          startLimitIntervalSec = 0;
          serviceConfig = serviceHardening // {
            Type = "simple";
            Restart = "always";
            RestartSec = "1s";
            ExecStartPre = [
              "${pkgs.coreutils}/bin/timeout 30 ${pkgs.bash}/bin/bash -c 'until [ -S /tmp/dbusproxy_net.sock ]; do sleep 0.5; done'"
            ];
            Environment = [
              "DBUS_SESSION_BUS_ADDRESS=unix:path=/tmp/dbusproxy_net.sock"
            ];
            ExecStart = [
              ''
                ${lib.getExe pkgs.dbus-proxy} \
                  --source-bus-name ${busName} \
                  --source-object-path /org/ghaf/FortiVpn \
                  --proxy-bus-name ${busName} \
                  --source-bus-type session \
                  --target-bus-type system \
                  --log-level error
              ''
            ];
          };
        };
      })

      (lib.mkIf isNetVm {
        networking.networkmanager = {
          enable = true;
          plugins = [ backendPackage ];
          unmanaged = [
            config.ghaf.networking.hosts.${config.networking.hostName}.interfaceName
          ];
        };

        givc.dbusproxy.system.policy.talk = [ busName ];

        ghaf = {
          storagevm.directories = lib.mkIf config.ghaf.storagevm.enable (
            [ certificateDirectory ]
            ++ lib.optional (!config.ghaf.services.wifi.enable) "/etc/NetworkManager/system-connections/"
          );
          security.audit.extraRules = [
            "-w ${certificateDirectory}/ -p wa -k fortivpn-certificates"
            "-w /etc/NetworkManager/system-connections/ -p wa -k networkmanager-connections"
          ];
        };

        systemd.tmpfiles.rules = [ "d ${certificateDirectory} 0700 root root -" ];

        services.dbus.packages = [
          (mkDbusPolicyPackage "ghaf-fortivpn-service" ''
            <policy user="${proxyUser}">
              <allow send_destination="${busName}" send_interface="${interfaceName}"/>
              <allow send_destination="${busName}" send_interface="org.freedesktop.DBus.Introspectable"/>
              <allow send_destination="${busName}" send_interface="org.freedesktop.DBus.Properties"/>
            </policy>
          '')
        ];

        systemd.services.ghaf-fortivpn = {
          description = "Ghaf Fortinet VPN profile service";
          after = [ "NetworkManager.service" ];
          requires = [ "NetworkManager.service" ];
          wantedBy = [ "multi-user.target" ];
          serviceConfig = serviceHardening // {
            Type = "dbus";
            BusName = busName;
            ExecStart = lib.getExe pkgs.ghaf-fortivpn-service;
            Environment = [ "GHAF_FORTIVPN_STATE_DIRECTORY=${certificateDirectory}" ];
            StateDirectory = "ghaf/fortivpn";
            StateDirectoryMode = "0700";
            PrivateTmp = true;
          };
        };
      })
    ]
  );
}
