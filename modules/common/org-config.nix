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
        management.fleet.url = mkOptionEntry types.str "Fleet MDM server base URL; null disables Orbit enrollment.";
        identity = {
          ssh = {
            debugKeys = mkOptionEntry (types.listOf types.str) ''
              Development SSH key roster. Forwarded unconditionally, inert unless that stack is enabled
            '';
            releaseKeys = mkOptionEntry (types.listOf types.str) ''
              Static SSH keys for the hardened release stack, inert unless that stack is enabled.
            '';
            trustedUserCAKeys = mkOptionEntry (types.listOf types.str) "SSH user-CA public keys for release SSH certificate auth.";
            allowedPrincipals = mkOptionEntry (types.listOf types.str) "Accepted certificate principals (null = module default: the admin user).";
            authorizedKeysOptions = mkOptionEntry types.str ''
              authorized_keys per-key options prefix (null = module default, which
              requires hardware-backed keys via verify-required).
            '';
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
      ghaf.services.orbit.fleetUrl = fwd org.management.fleet.url;

      ghaf.security.ssh.debug.authorizedKeys = fwd org.identity.ssh.debugKeys;
      ghaf.security.ssh.release.authorizedKeys = fwd org.identity.ssh.releaseKeys;
      ghaf.security.ssh.release.trustedUserCAKeys = fwd org.identity.ssh.trustedUserCAKeys;
      ghaf.security.ssh.release.allowedPrincipals = fwd org.identity.ssh.allowedPrincipals;
      ghaf.security.ssh.release.authorizedKeysOptions = fwd org.identity.ssh.authorizedKeysOptions;
    }
  ];
}
