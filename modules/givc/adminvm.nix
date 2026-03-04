# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{ config, lib, ... }:
let
  cfg = config.ghaf.givc.adminvm;
  policycfg = config.ghaf.givc.policyAdmin;

  inherit (lib)
    flatten
    foldl'
    lists
    mapAttrsToList
    mkEnableOption
    mkIf
    ;
  inherit (config.ghaf.givc.adminConfig) name;
  inherit (config.ghaf.networking) hosts;
  inherit (config.networking) hostName;
  systemHosts = lists.subtractLists (config.ghaf.common.appHosts ++ [ name ]) (
    builtins.attrNames config.ghaf.networking.hosts
  );

  # Create a list of policies from all VMs
  policyList = flatten (
    mapAttrsToList (
      vmName: vmPoliciesMap:
      if vmPoliciesMap == { } then
        [ ]
      else
        mapAttrsToList (policyName: policyValue: {
          inherit vmName policyName;
          inherit (policyValue.updater) url poll_interval_secs;
        }) vmPoliciesMap
    ) config.ghaf.common.policies
  );

  /*
    Group policies by policy name in a givc compatible set of policies.
    Throw error if in the system, there are more than one policies with the same name
    different URL.
  */
  groupedPolicies = foldl' (
    acc: item:
    let
      existing =
        acc.${item.policyName} or {
          vms = [ ];
          perPolicyUpdater = {
            inherit (item) url poll_interval_secs;
          };
        };
    in
    acc
    // {
      ${item.policyName} = {
        vms = existing.vms ++ [ item.vmName ];

        perPolicyUpdater = {
          url =
            if (item.url == existing.perPolicyUpdater.url) then
              item.url
            else
              throw "Conflicting URL in policy ${item.policyName} for VM ${item.vmName}";

          poll_interval_secs =
            if (item.poll_interval_secs < existing.perPolicyUpdater.poll_interval_secs) then
              item.poll_interval_secs
            else
              existing.perPolicyUpdater.poll_interval_secs;
        };
      };
    }
  ) { } policyList;
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
