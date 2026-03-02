# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# SNI (StatusNotifierItem) system tray forwarding via GIVC socket proxy.
#
# Appvm side  — Port is auto-assigned based on this VM's position in
#               ghaf.common.appHosts (alphabetical, portBase + index).
#
# Guivm side  — Generates one socket proxy entry and one dbus-proxy-sni
#               systemd service per entry in ghaf.common.appHosts.
#               Services are activated on-demand via systemd path units,
#               so VMs without SNI do not cause repeated restart failures.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  sniCfg = config.ghaf.givc.sni;
  inherit (lib)
    getExe
    listToAttrs
    mkEnableOption
    mkIf
    mkMerge
    mkOption
    nameValuePair
    types
    optionalString
    ;
  inherit (config.ghaf.networking) hosts;
  inherit (config.networking) hostName;
  guivmName = "gui-vm";
  appUserUid = toString config.ghaf.users.appUser.uid;
  homedUid = toString config.ghaf.users.homedUser.uid;

  # Port map: built from sniCfg.vms so ports start at portBase regardless of
  # where the VM falls in the full appHosts list.
  # sniCfg.vms defaults to ghaf.common.sniVms which is the same on all VMs,
  # so appvm and guivm will always agree on port assignments.
  portMap = listToAttrs (
    lib.imap0 (i: vmName: nameValuePair vmName (toString (sniCfg.portBase + i))) sniCfg.vms
  );

  # Guivm-side source descriptors: one per SNI-capable VM
  sniSources = map (vmName: {
    inherit vmName;
    port = portMap.${vmName};
    socket = "/tmp/dbusproxy-sni-${vmName}.sock";
  }) sniCfg.vms;

in
{
  _file = ./sni.nix;

  options.ghaf.givc.sni = {
    enable = mkEnableOption "SNI (StatusNotifierItem) tray icon forwarding via GIVC socket proxy";

    portBase = mkOption {
      type = types.int;
      default = 9030;
      description = ''
        Base TCP port for SNI socket proxy tunnels.
        Each appvm in ghaf.common.appHosts (alphabetical order) gets
        portBase + index as its dedicated port on gui-vm.
      '';
    };

    socket = mkOption {
      type = types.str;
      default = "/tmp/dbusproxy_sni.sock";
      description = "Local unix socket path for the SNI dbusproxy on the appvm side.";
    };

    vms = mkOption {
      type = types.listOf types.str;
      default = config.ghaf.common.sniVms;
      defaultText = lib.literalExpression "config.ghaf.common.sniVms";
      description = ''
        Appvms that have SNI enabled, as seen from the gui-vm side.
        Defaults to ghaf.common.sniVms which is auto-derived at host level
        from each appvm's ghaf.givc.sni.enable setting.
        Only these VMs will get a socket proxy entry and a dbus-proxy-sni
        service on gui-vm. Ports are derived from their position in
        ghaf.common.appHosts to stay consistent with the appvm side.
      '';
    };
  };

  config = mkMerge [

    # Appvm side
    (mkIf (sniCfg.enable && config.ghaf.givc.appvm.enable && config.ghaf.givc.enable) (
      let
        appVmPort = portMap.${hostName};
      in
      {
        # Tunnel the local SNI dbusproxy socket to gui-vm at our auto-assigned port
        givc.appvm.capabilities.socketProxy = {
          enable = true;
          sockets = [
            {
              transport = {
                name = guivmName;
                addr = hosts.${guivmName}.ipv4;
                port = appVmPort;
                protocol = "tcp";
              };
              inherit (sniCfg) socket;
            }
          ];
        };

        # SNI renamer: runs on the real session bus, owns org.kde.StatusNotifierWatcher,
        # and acquires dot-based well-known names (org.kde.StatusNotifierItem.proxy_<pid>_<n>)
        # for every SNI app — including apps such as Element and Discord that register
        # with their unique D-Bus name (:1.X) instead of a well-known name.
        # This lets the GIVC tunnel xdg-dbus-proxy run with filter=true and
        # --talk=org.kde.StatusNotifierItem.* (which requires dot-separated names).
        systemd.services.dbus-proxy-sni-renamer = {
          description = "SNI renamer for ${hostName}: bridge unique-name tray apps to well-known names";
          after = [ "dbus.socket" ];
          requires = [ "dbus.socket" ];
          wantedBy = [ "multi-user.target" ];

          serviceConfig = {
            Type = "exec";
            Restart = "always";
            RestartSec = "30s";
            User = appUserUid;
            Environment = [
              "DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/${appUserUid}/bus"
              "XDG_DATA_DIRS=/run/current-system/sw/share"
            ];
            ExecStart = "${lib.getExe pkgs.dbus-proxy} --renamer-mode";
          };
          startLimitIntervalSec = 0;
        };

        # dbusproxy: expose a filtered session bus socket for the GIVC tunnel
        givc.dbusproxy = {
          enable = true;
          session = {
            enable = true;
            user = config.ghaf.users.appUser.name;
            inherit (sniCfg) socket;
            policy = {
              own = [ "org.kde.StatusNotifierWatcher" ];
              talk = [
                # Talk to renamer-assigned item names (org.kde.StatusNotifierItem.proxy_*)
                # Receive StatusNotifierItemRegistered/Unregistered signals from renamer (org.kde.StatusNotifierWatcher)
                # Well-known names such as org.kde.StatusNotifierItem-6-2
                "org.kde.*"
              ];
            };
          };
        };
      }
    ))

    # Guivm side
    (mkIf
      (sniCfg.enable && config.ghaf.givc.guivm.enable && config.ghaf.givc.enable && sniSources != [ ])
      {

        # Socket proxy entries: one per appvm in appHosts
        givc.sysvm.capabilities.socketProxy.sockets = map (src: {
          transport = {
            name = src.vmName;
            addr = hosts.${src.vmName}.ipv4;
            inherit (src) port;
            protocol = "tcp";
          };
          inherit (src) socket;
        }) sniSources;

        # Path units: activate the dbus-proxy-sni service only when the tunnel
        # socket actually appears (i.e., the appvm has SNI enabled and is running).
        # This prevents restart-loops for appvms that have SNI disabled.
        systemd.paths = listToAttrs (
          map (
            src:
            nameValuePair "dbus-proxy-sni-${src.vmName}" {
              description = "Watch for SNI tunnel socket from ${src.vmName}";
              wantedBy = [ "graphical.target" ];
              pathConfig = {
                PathExists = src.socket;
                Unit = "dbus-proxy-sni-${src.vmName}.service";
              };
            }
          ) sniSources
        );

        # One dbus-proxy-sni service per appvm: bridges the GIVC tunnel socket
        # (system bus) to the user session bus so the compositor sees the tray icons.
        # Activated on-demand by the corresponding path unit above.
        systemd.services = listToAttrs (
          map (
            src:
            nameValuePair "dbus-proxy-sni-${src.vmName}" {
              description = "DBus proxy for SNI tray icons from ${src.vmName}";
              after = [ "user-login.service" ];
              serviceConfig = {
                Type = "exec";
                Restart = "on-failure";
                RestartSec = "5s";
                Environment = [
                  "DBUS_SYSTEM_BUS_ADDRESS=unix:path=${src.socket}"
                  "DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/${homedUid}/bus"
                ];
                User = homedUid;
                ExecStart = ''
                  ${getExe pkgs.dbus-proxy} \
                    --sni-mode \
                    --source-bus-type system \
                    --target-bus-type session ${optionalString config.ghaf.profiles.debug.enable "--log-level=verbose"}
                '';
              };
            }
          ) sniSources
        );
      }
    )

  ];
}
