# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.ghaf.givc.guivm;
in
{
  _file = ./dbus-proxy.nix;

  options.ghaf.givc.guivm.dbusProxies = lib.mkOption {
    default = { };
    description = ''
      D-Bus services exposed on the GUI VM system bus through existing GIVC
      sockets. Each entry creates a dbus-proxy-<name> systemd service.
      Socket transport and D-Bus access policies are configured separately.
      Override service settings through systemd.services.dbus-proxy-<name>.
    '';
    type = lib.types.attrsOf (
      lib.types.submodule {
        options = {
          description = lib.mkOption {
            type = lib.types.str;
            description = "Description of the proxy systemd service.";
          };
          busName = lib.mkOption {
            type = lib.types.str;
            description = "D-Bus name to proxy, unchanged on the GUI VM system bus.";
          };
          objectPath = lib.mkOption {
            type = lib.types.str;
            description = "Root object path to proxy from the source bus.";
          };
          socket = lib.mkOption {
            type = lib.types.str;
            description = "Path to the source bus socket provided by GIVC.";
          };
        };
      }
    );
  };

  config = lib.mkIf (cfg.enable && config.ghaf.givc.enable) {
    systemd.services = lib.mapAttrs' (
      name: proxy:
      let
        waitForSocket = pkgs.writeShellApplication {
          name = "dbus-proxy-${name}-wait";
          runtimeInputs = [ pkgs.coreutils ];
          text = ''
            until [ -S ${lib.escapeShellArg proxy.socket} ]; do
              sleep 0.5
            done
          '';
        };
        startProxy = pkgs.writeShellApplication {
          name = "dbus-proxy-${name}-start";
          runtimeInputs = [ pkgs.dbus-proxy ];
          text = ''
            exec dbus-proxy \
              --source-bus-name ${lib.escapeShellArg proxy.busName} \
              --source-object-path ${lib.escapeShellArg proxy.objectPath} \
              --proxy-bus-name ${lib.escapeShellArg proxy.busName} \
              --source-bus-type session \
              --target-bus-type system \
              --log-level error
          '';
        };
      in
      lib.nameValuePair "dbus-proxy-${name}" {
        inherit (proxy) description;
        after = [ "givc-${config.networking.hostName}.service" ];
        requires = [ "givc-${config.networking.hostName}.service" ];
        wantedBy = [ "multi-user.target" ];
        startLimitIntervalSec = lib.mkDefault 0;
        serviceConfig = {
          Type = "simple";
          Restart = lib.mkDefault "always";
          RestartSec = lib.mkDefault "1s";
          ExecStartPre = [
            "${pkgs.coreutils}/bin/timeout 30 ${lib.getExe waitForSocket}"
          ];
          Environment = [ "DBUS_SESSION_BUS_ADDRESS=unix:path=${proxy.socket}" ];
          ExecStart = [ (lib.getExe startProxy) ];
        };
      }
    ) cfg.dbusProxies;
  };
}
