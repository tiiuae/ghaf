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
  vmEntry = vm: builtins.filter (x: x.name == vm) config.ghaf.networking.hosts.entries;
  address = vm: lib.head (builtins.map (x: x.ip) (vmEntry vm));
in
{
  options.ghaf.givc.host = {
    enable = mkEnableOption "Enable host givc module.";
  };

  config = mkIf (cfg.enable && config.ghaf.givc.enable) {
    # Configure host service
    givc.host = {
      enable = true;
      inherit (config.ghaf.givc) debug;
      agent = {
        name = hostName;
        addr = address hostName;
        port = "9000";
      };
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
