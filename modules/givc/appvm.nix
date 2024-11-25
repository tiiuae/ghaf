# Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  config,
  lib,
  givc,
  ...
}:
let
  cfg = config.ghaf.givc.appvm;
  inherit (lib)
    mkOption
    mkEnableOption
    mkIf
    types
    head
    filter
    strings
    ;
  getIp =
    name: head (map (x: x.ip) (filter (x: x.name == name) config.ghaf.networking.hosts.entries));
  admin = head (filter (x: strings.hasInfix ".100." x.addr) config.ghaf.givc.adminConfig.addresses);
in
{
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
      inherit admin;
      agent = {
        name = config.networking.hostName;
        addr = getIp config.networking.hostName;
        port = "9000";
      };
      inherit (cfg) applications;
      tls.enable = config.ghaf.givc.enableTls;
    };

    # Quick fix to allow linger (linger option in user def. currently doesn't work, e.g., bc mutable)
    systemd.tmpfiles.rules = [ "f /var/lib/systemd/linger/${config.ghaf.users.accounts.user}" ];
  };
}
