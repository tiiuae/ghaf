# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# ghaf.org - organization/deployment-specific configuration.
#
# This module is a collection of org-specific parameters that are distributed
# across the guests.
#
# The hosts ghaf.org is transported via global-config.org. Every VM receives
# global-config as the globalConfig specialArg; this module assigns the transport
# copy back into config.ghaf.org.
#
# The ghaf.org schema: every value an organization can supply. `null` is the
# "unset" marker, so an empty list or attrset means "explicitly none" and
# is forwarded as such. To add an org value, declare it as a new option and
# forward it.
{
  config,
  lib,
  ...
}@args:
let
  inherit (lib) types;

  globalConfig = args.globalConfig or null;
  org = config.ghaf.org;
  fwd = v: lib.mkIf (v != null) v;

  mkOptionEntry =
    type: description:
    lib.mkOption {
      type = types.nullOr type;
      default = null;
      inherit description;
    };
in
{
  _file = ./org-config.nix;

  options.ghaf.org = lib.mkOption {
    type = types.submodule {
      options = {
        telemetry = {
          logging = {
            endpoint = mkOptionEntry types.str "Loki push endpoint URL; null disables log forwarding.";
            serverName = mkOptionEntry types.str "Expected TLS server name (SNI) for the logging endpoint.";
            logseald.revokedPeerKeys = mkOptionEntry (types.listOf (types.strMatching "spki-sha256:[0-9a-f]{64}")) ''
              Revoked logseald peer leaf keys (SPKI SHA-256), enforced offline by
              every producer and sealer; null revokes none.
            '';
          };
          bugReport = {
            owner = mkOptionEntry types.str "GitHub owner of the bug-report repository; null disables bug reporting.";
            repo = mkOptionEntry types.str "GitHub bug-report repository name; null disables bug reporting.";
          };
        };
      };
    };
    default = { };
    description = "Organization/deployment-specific configuration.";
  };

  config = lib.mkMerge [
    (lib.mkIf (globalConfig != null) { ghaf.org = globalConfig.org; })
    {
      ghaf.logging.server.endpoint = fwd org.telemetry.logging.endpoint;
      ghaf.logging.server.tls.serverName = fwd org.telemetry.logging.serverName;
      ghaf.logging.logseald.tls.revokedPeerKeys = fwd org.telemetry.logging.logseald.revokedPeerKeys;
      ghaf.services.github.owner = fwd org.telemetry.bugReport.owner;
      ghaf.services.github.repo = fwd org.telemetry.bugReport.repo;
    }
  ];
}
