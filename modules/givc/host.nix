# Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  config,
  lib,
  givc,
  ...
}:
let
  cfg = config.ghaf.givc.host;
  inherit (builtins) map filter attrNames;
  inherit (lib) mkEnableOption mkIf head;
  hostName = "ghaf-host-debug";
in
{
  options.ghaf.givc.host = {
    enable = mkEnableOption "Enable host givc module.";
  };

  config = mkIf (cfg.enable && config.ghaf.givc.enable) {
    # Configure host service
    givc.host =
      let
        getIp =
          name: head (map (x: x.ip) (filter (x: x.name == name) config.ghaf.networking.hosts.entries));
        addr = getIp hostName;
      in
      {
        enable = true;
        name = hostName;
        inherit addr;
        port = "9000";
        services = [
          "reboot.target"
          "poweroff.target"
          "suspend.target"
        ] ++ map (vmName: "microvm@${vmName}.service") (attrNames config.microvm.vms);
        tls.enable = config.ghaf.givc.enableTls;
        admin = config.ghaf.givc.adminConfig;
      };
  };
}
