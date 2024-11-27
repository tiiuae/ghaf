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
  inherit (builtins) map attrNames;
  inherit (lib)
    mkEnableOption
    mkIf
    head
    filter
    strings
    ;
  getIp =
    name: head (map (x: x.ip) (filter (x: x.name == name) config.ghaf.networking.hosts.debugEntries));
  adminAddress = head (
    filter (x: strings.hasInfix ".101." x.addr) config.ghaf.givc.adminConfig.addresses
  );
  agentAddresses =
    config.ghaf.networking.hosts.entries
    ++ (filter (x: lib.strings.hasInfix "host" x.name) config.ghaf.networking.hosts.debugEntries);
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
      admin = {
        inherit (config.ghaf.givc.adminConfig) name;
        inherit (adminAddress) addr port protocol;
      };
      agent = {
        name = config.networking.hostName;
        addr = getIp config.networking.hostName;
        port = "9000";
      };
      services = [
        "reboot.target"
        "poweroff.target"
        "suspend.target"
      ] ++ map (vmName: "microvm@${vmName}.service") (attrNames config.microvm.vms);
      tls.enable = config.ghaf.givc.enableTls;
    };

    givc.tls = {
      enable = config.ghaf.givc.enableTls;
      agents = map (entry: {
        inherit (entry) name;
        addr = entry.ip;
      }) agentAddresses;
      adminTlsName = config.ghaf.givc.adminConfig.name;
      adminAddresses = config.ghaf.givc.adminConfig.addresses;
      generatorHostName = config.networking.hostName;
      storagePath = "/storagevm";
    };
  };
}
