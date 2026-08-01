# SPDX-FileCopyrightText: 2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  config,
  inputs,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.ghaf.services.fortivpn;
  isGuiVm = config.networking.hostName == "gui-vm";
  isNetVm = config.networking.hostName == "net-vm";
  certificateDirectory = "/var/lib/ghaf/fortivpn";
  resumeFile = "/run/ghaf-fortivpn-resume";
  nmcli = lib.getExe' pkgs.networkmanager "nmcli";
  editorPackage = pkgs.networkmanager-openconnect;
  busName = "org.ghaf.FortiVpn";
  authenticationBusName = "${busName}.Authentication";
  objectPath = "/org/ghaf/FortiVpn";
  interfaceName = "org.ghaf.FortiVpn1";
  createProfileMethod = "CreateProfile";
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
          {
            assertion = !isNetVm || config.ghaf.users.proxyUser.enable;
            message = "ghaf.services.fortivpn requires the D-Bus proxy user in net-vm";
          }
        ];
      }

      (lib.mkIf isGuiVm {
        nixpkgs.overlays = lib.mkAfter [ inputs.ghafpkgs.overlays.fortivpn-desktop ];

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
              <allow send_destination="${busName}" send_path="${objectPath}" send_interface="${interfaceName}" send_member="${createProfileMethod}"/>
              <allow send_destination="${busName}" send_path="${objectPath}" send_interface="${interfaceName}" send_member="PendingAuthentication"/>
              <allow send_destination="${busName}" send_path="${objectPath}" send_interface="${interfaceName}" send_member="AnswerAuthentication"/>
              <allow send_destination="${busName}" send_path="${objectPath}" send_interface="org.freedesktop.DBus.Introspectable" send_member="Introspect"/>
            </policy>
          '')
        ];

        ghaf.givc.guivm.dbusProxies.fortivpn = {
          description = "DBus proxy for the Fortinet VPN service in net-vm";
          inherit busName objectPath;
          socket = "/tmp/dbusproxy_net.sock";
        };

        systemd.services.dbus-proxy-fortivpn = {
          startLimitIntervalSec = 30;
          startLimitBurst = 5;
          serviceConfig = serviceHardening;
        };

      })

      (lib.mkIf isNetVm {
        # sleep-actions runs its main script to stop NetworkManager after preStart.
        systemd.services.sleep-actions.preStart = ''
          rm -f ${resumeFile} ${resumeFile}.sleep
          while IFS=: read -r uuid type state; do
            if [[ "$type:$state" == vpn:activated && -f ${certificateDirectory}/$uuid/auth.json ]]; then
              (umask 077; echo "$uuid" >> ${resumeFile}.sleep)
            fi
          done < <(LC_ALL=C ${nmcli} -t -f UUID,TYPE,STATE connection show --active)
        '';

        # Arm the dispatcher before NetworkManager starts bringing uplinks back.
        powerManagement.resumeCommands = lib.mkBefore ''
          if [[ -f ${resumeFile}.sleep ]]; then
            mv ${resumeFile}.sleep ${resumeFile}
          fi
        '';

        networking.networkmanager = {
          enable = true;
          plugins = [ pkgs.ghaf-networkmanager-openconnect ];
          unmanaged = [
            config.ghaf.networking.hosts.${config.networking.hostName}.interfaceName
          ];
          dispatcherScripts = [
            {
              type = "basic";
              source = pkgs.writeShellScript "fortivpn-resume" ''
                [[ -s ${resumeFile} ]] || exit 0
                case "$2" in
                  up|dhcp4-change|dhcp6-change|connectivity-change) ;;
                  *) exit 0 ;;
                esac
                # A surviving tunnel can report "up" while the physical uplink is still offline.
                case "$(LC_ALL=C ${nmcli} -g STATE general)" in
                  connected|'connected (site only)') ;;
                  *) exit 0 ;;
                esac

                mapfile -t profiles < ${resumeFile}
                : > ${resumeFile}
                for uuid in "''${profiles[@]}"; do
                  [[ -f ${certificateDirectory}/$uuid/auth.json ]] || continue
                  ${nmcli} -g UUID connection show --active | ${pkgs.gnugrep}/bin/grep -Fxq "$uuid" && continue
                  ${nmcli} --wait 0 connection up uuid "$uuid" || echo "$uuid" >> ${resumeFile}
                done
                [[ -s ${resumeFile} ]] || ${pkgs.coreutils}/bin/rm -f ${resumeFile}
              '';
            }
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
          # dbus-proxy discovers the object tree by introspecting each ancestor from the root.
          (mkDbusPolicyPackage "ghaf-fortivpn-service" ''
            <policy context="default">
              <deny own="${authenticationBusName}"/>
              <deny send_destination="${authenticationBusName}"/>
            </policy>
            <policy user="root">
              <allow own="${authenticationBusName}"/>
              <allow send_destination="${authenticationBusName}"/>
            </policy>
            <policy user="${proxyUser}">
              <allow send_destination="${busName}" send_path="${objectPath}" send_interface="${interfaceName}" send_member="${createProfileMethod}"/>
              <allow send_destination="${busName}" send_path="${objectPath}" send_interface="${interfaceName}" send_member="PendingAuthentication"/>
              <allow send_destination="${busName}" send_path="${objectPath}" send_interface="${interfaceName}" send_member="AnswerAuthentication"/>
              <allow send_destination="${busName}" send_path="/" send_interface="org.freedesktop.DBus.Introspectable" send_member="Introspect"/>
              <allow send_destination="${busName}" send_path="/org" send_interface="org.freedesktop.DBus.Introspectable" send_member="Introspect"/>
              <allow send_destination="${busName}" send_path="/org/ghaf" send_interface="org.freedesktop.DBus.Introspectable" send_member="Introspect"/>
              <allow send_destination="${busName}" send_path="${objectPath}" send_interface="org.freedesktop.DBus.Introspectable" send_member="Introspect"/>
            </policy>
          '')
        ];

        systemd.services.ghaf-fortivpn = {
          description = "Ghaf Fortinet VPN profile and authentication service";
          after = [ "NetworkManager.service" ];
          wants = [ "NetworkManager.service" ];
          wantedBy = [ "multi-user.target" ];
          serviceConfig = serviceHardening // {
            Type = "dbus";
            BusName = busName;
            ExecStart = lib.getExe pkgs.ghaf-fortivpn-service;
            Environment = [ "GHAF_FORTIVPN_STATE_DIRECTORY=${certificateDirectory}" ];
            Restart = "on-failure";
            RestartSec = "1s";
            StateDirectory = "ghaf/fortivpn";
            StateDirectoryMode = "0700";
            PrivateTmp = true;
            PrivateNetwork = false;
            RestrictAddressFamilies = [
              "AF_UNIX"
              "AF_INET"
              "AF_INET6"
            ];
          };
        };

      })
    ]
  );
}
