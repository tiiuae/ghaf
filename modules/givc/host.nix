# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  config,
  lib,
  ...
}:
let
  cfg = config.ghaf.givc.host;
  policycfg = config.ghaf.givc.policyClient;
  inherit (lib)
    mapAttrs
    mkEnableOption
    mkIf
    optionalString
    optionals
    ;
in
{
  _file = ./host.nix;

  options.ghaf.givc.host = {
    enable = mkEnableOption "Enable host givc module.";
  };

  config = mkIf (cfg.enable && config.ghaf.givc.enable) {
    assertions = [
      {
        assertion = !config.ghaf.givc.policyAdmin.enable;
        message = "Policy admin cannot be enabled in host.";
      }
    ];
    givc.host = {
      enable = true;

      inherit (config.ghaf.givc) debug;
      network = {
        agent.transport = {
          name = config.networking.hostName;
          addr = config.ghaf.networking.hosts.${config.networking.hostName}.ipv4;
          port = "9000";
        };
        tls.enable = config.ghaf.givc.enableTls;
        admin.transport = lib.head config.ghaf.givc.adminConfig.addresses;
      };
      capabilities = {
        services = [
          "reboot.target"
          "poweroff.target"
          "suspend.target"
        ]
        ++ optionals config.ghaf.services.performance.host.tuned.enable [
          "host-powersave.service"
          "host-balanced.service"
          "host-performance.service"
          "host-powersave-battery.service"
          "host-balanced-battery.service"
          "host-performance-battery.service"
        ];
        vmServices = {
          adminVm = optionalString (
            config.ghaf.common.adminHost != null
          ) "microvm@${config.ghaf.common.adminHost}.service";
          systemVms = map (vmName: "microvm@${vmName}.service") config.ghaf.common.systemHosts;
          appVms = map (vmName: "microvm@${vmName}.service") config.ghaf.common.appHosts;
        };
        exec.enable = true;
        policy = mkIf policycfg.enable {
          enable = true;
          inherit (policycfg) storePath;
          policies = mapAttrs (_name: value: value.dest) policycfg.policies;
        };
      };
    };

    givc.tls = {
      enable = config.ghaf.givc.enableTls;
      agents = lib.attrsets.mapAttrsToList (n: v: {
        name = n;
        addr = v.ipv4;
      }) config.ghaf.networking.hosts;
      generatorHostName = config.networking.hostName;
      storagePath = "/persist/storagevm/givc";
    };

    ghaf.security.audit.extraRules = [
      "-w /etc/givc/ -p wa -k givc-${config.networking.hostName}"
    ];
  };
}
