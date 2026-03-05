# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  config,
  lib,
  ...
}:
let
  cfg = config.ghaf.givc.appvm;
  inherit (lib)
    mkOption
    mkEnableOption
    mkIf
    types
    ;
  inherit (config.ghaf.networking) hosts;
  inherit (config.networking) hostName;
  guivmName = "gui-vm";
in
{
  _file = ./appvm.nix;

  options.ghaf.givc.appvm = {
    enable = mkEnableOption "Enable appvm givc module.";
    applications = mkOption {
      type = types.listOf types.attrs;
      default = [ { } ];
      description = "Applications to run in the appvm.";
    };
  };

  config = mkIf (cfg.enable && config.ghaf.givc.enable) {
    # Configure appvm service
    givc.appvm = {
      enable = true;
      inherit (config.ghaf.givc) debug;
      inherit (config.ghaf.users.homedUser) uid;
      transport = {
        name = hostName;
        addr = hosts.${hostName}.ipv4;
        port = "9000";
      };
      socketProxy = [
        {
          transport = {
            name = guivmName;
            addr = hosts.${guivmName}.ipv4;
            port = "9030";
            protocol = "tcp";
          };
          socket = "/tmp/dbusproxy_sni.sock";
        }
      ];
      inherit (cfg) applications;
      tls.enable = config.ghaf.givc.enableTls;
      admin = lib.head config.ghaf.givc.adminConfig.addresses;
    };
    givc.dbusproxy = {
      enable = true;
      session = {
        enable = true;
        user = config.ghaf.users.appUser.name;
        socket = "/tmp/dbusproxy_sni.sock";
        # filter = false is intentional for this socket:
        #    Unique-name apps cannot be filtered: applications such as Element, Chromium,
        #    Discord and other Electron-based apps register StatusNotifierItem with their
        #    D-Bus unique name (e.g. :1.6) and never acquire a well-known org.kde.* name.
        #    xdg-dbus-proxy policy grants TALK only to well-known names, so these apps
        #    would be silently blocked regardless of the rules configured. filter = false
        #    (transparent mode) is the only way to support all SNI clients correctly.
        filter = false;
      };
    };
    ghaf.security.audit.extraRules = [
      "-w /etc/givc/ -p wa -k givc-${hostName}"
    ];
  };
}
