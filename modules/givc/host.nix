# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  config,
  lib,
  ...
}:
let
  cfg = config.ghaf.givc.host;
  inherit (builtins) map;
  inherit (lib)
    head
    mkEnableOption
    mkIf
    optionalString
    ;
  inherit (config.networking) hostName;
  inherit (config.ghaf.networking) hosts;
  inherit (config.ghaf.common) adminHost;
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
      ];
      adminVm = optionalString (adminHost != null) "microvm@${adminHost}.service";
      systemVms = map (vmName: "microvm@${vmName}.service") config.ghaf.common.systemHosts;
      appVms = map (vmName: "microvm@${vmName}.service") config.ghaf.common.appHosts;
      tls.enable = config.ghaf.givc.enableTls;
      admin = head config.ghaf.givc.adminConfig.addresses;
    };

    givc.tls = {
      enable = config.ghaf.givc.enableTls;
      agents = lib.attrsets.mapAttrsToList (n: v: {
        name = n;
        addr = v.ipv4;
      }) hosts;
      generatorHostName = hostName;
      storagePath = "/persist/storagevm/givc";
    };

    ghaf.security.audit.extraRules = [
      "-w /etc/givc/ -p wa -k givc-${hostName}"
    ];
  };
}
