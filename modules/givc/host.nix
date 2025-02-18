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
    ;
  inherit (config.networking) hostName;
  inherit (config.ghaf.networking) hosts;
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
      transport = {
        name = hostName;
        addr = hosts.${hostName}.ipv4;
        port = "9000";
      };
      services = [
        "reboot.target"
        "poweroff.target"
        "suspend.target"
      ] ++ map (vmName: "microvm@${vmName}.service") (attrNames config.microvm.vms);
      tls.enable = config.ghaf.givc.enableTls;
      admin = head config.ghaf.givc.adminConfig.addresses;
    };

    givc.tls = {
      enable = config.ghaf.givc.enableTls;
      agents = lib.attrsets.mapAttrsToList (n: v: {
        name = n;
        addr = v.ipv4;
      }) hosts;
      adminTlsName = config.ghaf.givc.adminConfig.name;
      adminAddresses = config.ghaf.givc.adminConfig.addresses;
      generatorHostName = hostName;
      storagePath = "/persist/storagevm/givc";
    };
  };
}
