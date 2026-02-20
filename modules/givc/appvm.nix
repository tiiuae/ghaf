# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  config,
  lib,
  ...
}:
let
  cfg = config.ghaf.givc.appvm;
  policycfg = config.ghaf.givc.policyClient;
  inherit (lib)
    mkOption
    mkEnableOption
    mkIf
    types
    mapAttrs
    ;
  inherit (config.ghaf.networking) hosts;
  inherit (config.networking) hostName;
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
    assertions = [
      {
        assertion = !config.ghaf.givc.policyAdmin.enable;
        message = "Policy admin cannot be enabled in appvm.";
      }
    ];
    # Configure appvm service
    givc.appvm = {
      enable = true;
      inherit (config.ghaf.givc) debug;
      inherit (config.ghaf.users.homedUser) uid;
      network = {
        agent.transport = {
          name = hostName;
          addr = hosts.${hostName}.ipv4;
          port = "9000";
        };
        admin.transport = lib.head config.ghaf.givc.adminConfig.addresses;
        tls.enable = config.ghaf.givc.enableTls;
      };
      capabilities = {
        inherit (cfg) applications;

        policy = mkIf policycfg.enable {
          enable = true;
          inherit (policycfg) storePath;
          policies = mapAttrs (_name: value: value.dest) policycfg.policies;
        };
      };
    };
    ghaf.security.audit.extraRules = [
      "-w /etc/givc/ -p wa -k givc-${hostName}"
    ];
  };
}
