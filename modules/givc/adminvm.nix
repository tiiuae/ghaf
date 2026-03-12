# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{ config, lib, ... }:
let
  cfg = config.ghaf.givc.adminvm;
  policycfg = config.ghaf.givc.policyAdmin;

  inherit (lib)
    lists
    mkEnableOption
    mkIf
    ;
  inherit (config.ghaf.givc.adminConfig) name;
  inherit (config.ghaf.networking) hosts;
  inherit (config.networking) hostName;
  systemHosts = lists.subtractLists (config.ghaf.common.appHosts ++ [ name ]) (
    builtins.attrNames config.ghaf.networking.hosts
  );
  policyList = lib.concatLists (
    lib.mapAttrsToList (
      vmName:
      lib.mapAttrsToList (
        policyName: policyValue: {
          inherit vmName policyName;
          inherit (policyValue.updater) url poll_interval_secs;
        }
      )
    ) config.ghaf.common.policies
  );

  groupedPolicies = lib.mapAttrs (
    policyName: items:
    let
      urls = lib.unique (map (i: i.url) items);
      polls = map (i: i.poll_interval_secs) items;
    in
    if lib.length urls > 1 then
      throw "Conflicting URLs in policy ${policyName}: ${toString urls}"
    else
      {
        vms = map (i: i.vmName) items;
        perPolicyUpdater = {
          url = lib.head urls;
          poll_interval_secs = lib.foldl' lib.min (lib.head polls) polls;
        };
      }
  ) (builtins.groupBy (i: i.policyName) policyList);
in
{
  _file = ./adminvm.nix;

  options.ghaf.givc.adminvm = {
    enable = mkEnableOption "Enable adminvm givc module.";
  };

  config = mkIf (cfg.enable && config.ghaf.givc.enable) {
    assertions = [
      {
        assertion = !config.ghaf.givc.policyClient.enable;
        message = "Policy client is not supported in adminvm.";
      }
    ];

    # Configure admin service
    givc.admin = {
      enable = true;
      inherit (config.ghaf.givc) debug;
      inherit name;
      inherit (config.ghaf.givc.adminConfig) addresses;
      services = map (host: "givc-${host}.service") systemHosts;
      tls.enable = config.ghaf.givc.enableTls;
      policyAdmin = mkIf policycfg.enable {
        enable = true;
        inherit (policycfg) storePath updater;
        policies = groupedPolicies;
      };
    };

    # Sysvm agent so admin-vm receives timezone/locale propagation
    givc.sysvm = {
      enable = true;
      inherit (config.ghaf.givc) debug;
      network = {
        agent.transport = {
          name = hostName;
          addr = hosts.${hostName}.ipv4;
          port = "9000";
        };
        tls.enable = config.ghaf.givc.enableTls;
        admin.transport = lib.head config.ghaf.givc.adminConfig.addresses;
      };

      capabilities = {
        services = [
          "poweroff.target"
          "reboot.target"
        ];
      };

    };

    ghaf.security.audit.extraRules = [
      "-w /etc/givc/ -p wa -k givc-${name}"
    ];

  };
}
