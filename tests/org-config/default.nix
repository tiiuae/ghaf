# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# Eval-only delivery check for the ghaf.org translation layer
# (modules/common/org). An org value set on the host must:
#  1. hydrate config.ghaf.org inside every guest kind (sysvm and appvm) via the
#     global-config wire, and
#  2. be forwarded into the canonical module options at plain priority, so
#     rosters merge with a direct definition and a scalar collides with one.
#
# Forwarding never gates on image posture; the consuming modules do. The
# dev-key assertions below pin both halves of that: the roster reaches the
# option on every image, and only a debug image installs it.
#
# Uses intel-laptop-debug as-is: the laptop target family enables
# reference.org.tii (targets/laptop/flake-module.nix), so the host's ghaf.org
# already carries a real endpoint; the test only asserts that the same value
# arrives everywhere it is supposed to.
{
  self,
  lib,
  runCommand,
}:
let
  host = self.nixosConfigurations.intel-laptop-debug.config;
  releaseHost = self.nixosConfigurations.intel-laptop-release.config;

  adminVm = host.microvm.vms."admin-vm".evaluatedConfig.config;
  appVm = host.microvm.vms."flatpak-vm".evaluatedConfig.config;
  guiVm = host.microvm.vms."gui-vm".evaluatedConfig.config;

  org = host.ghaf.org;
  orgEndpoint = org.telemetry.logging.endpoint;
  orgServerName = org.telemetry.logging.serverName;
  orgBugReport = org.telemetry.bugReport;
  orgFleetUrl = org.management.fleet.url;
  orgDevKeys = org.identity.ssh.debugKeys;

  # Org domains are deferred modules, so the org's own values are only readable
  # once the canonical option has evaluated them.
  adName = lib.head (lib.attrNames org.identity.activeDirectory.domains);
  orgAd = host.ghaf.users.active-directory.domains.${adName};
  guiAdDomain = guiVm.ghaf.users.active-directory.domains.${adName};

  # An override through ghaf.org must reach the host and every VM. mkForce
  # because the value overridden here is one tii.nix already sets; an org value
  # the reference leaves unset needs no priority. The same extended host carries
  # an org user-CA key (TII sets none in-tree) to prove list-valued release-SSH
  # material crosses the wire, an org admin credential to prove the hash
  # actually reaches the user, and a direct partial definition of the org's AD
  # domain to prove submodule-valued org data merges leaf-wise.
  overridden = "https://override.example/loki/api/v1/push";
  revokedPeerKey = "spki-sha256:0000000000000000000000000000000000000000000000000000000000000000";
  caTestKey = "ssh-ed25519 AAAATESTKEY org-config-test";
  extraDevKey = "ssh-ed25519 AAAAEXTRAKEY org-config-test-extra";

  shadowHost =
    (self.nixosConfigurations.intel-laptop-debug.extendModules {
      modules = [
        {
          _file = "org-config-test-shadow";
          ghaf.org = {
            telemetry.logging.endpoint = lib.mkForce overridden;
            telemetry.logging.logseald.revokedPeerKeys = [ revokedPeerKey ];
            identity.ssh.trustedUserCAKeys = [ caTestKey ];
            network.ntpServers = [ "ntp.org-config-test" ];
            locale = {
              defaultLocale = "de_DE.UTF-8";
              timeZone = "Asia/Dubai";
            };
            identity.admin = {
              name = "orgadmin";
              hashedPassword = "org-config-test-hash";
            };
          };
          # Rosters merge: this must land alongside the org dev keys, not
          # replace them.
          ghaf.security.ssh.debug.authorizedKeys = [ extraDevKey ];
          ghaf.users.active-directory.domains.${adName} = {
            ldap.baseDn = "dc=direct";
            ad.gpoAccessControl = "enforcing";
          };
        }
      ];
    }).config;
  shadowAdminVm = shadowHost.microvm.vms."admin-vm".evaluatedConfig.config;
  shadowAdDomain = shadowHost.ghaf.users.active-directory.domains.${adName};

  conflictHost =
    (self.nixosConfigurations.intel-laptop-debug.extendModules {
      modules = [
        {
          _file = "org-config-test-conflict";
          ghaf.logging.server.endpoint = "https://conflict.example/loki/api/v1/push";
        }
      ];
    }).config;

  assertions = [
    {
      name = "tii org module populates the host's ghaf.org endpoint";
      ok = orgEndpoint != null;
    }
    {
      name = "sysvm (admin-vm) hydrates ghaf.org from the global-config wire";
      ok = adminVm.ghaf.org.telemetry.logging.endpoint == orgEndpoint;
    }
    {
      name = "appvm hydrates ghaf.org from the global-config wire";
      ok = appVm.ghaf.org.telemetry.logging.endpoint == orgEndpoint;
    }
    {
      name = "org endpoint is forwarded into ghaf.logging.server.endpoint in admin-vm";
      ok = adminVm.ghaf.logging.server.endpoint == orgEndpoint;
    }
    {
      name = "org serverName is forwarded into ghaf.logging.server.tls.serverName in admin-vm";
      ok = orgServerName != null && adminVm.ghaf.logging.server.tls.serverName == orgServerName;
    }
    {
      name = "forwarder is enabled when an org endpoint is present";
      ok = adminVm.ghaf.logging.server.enable;
    }
    {
      name = "an override of a reference org value reaches the host and the VMs alike";
      ok =
        shadowHost.ghaf.logging.server.endpoint == overridden
        && shadowAdminVm.ghaf.logging.server.endpoint == overridden;
    }
    {
      name = "an org logseald revocation list reaches the canonical option in a VM";
      ok = shadowAdminVm.ghaf.logging.logseald.tls.revokedPeerKeys == [ revokedPeerKey ];
    }
    {
      # The forward is plain priority, so the module system rejects a direct
      # definition instead of letting the host and the VMs disagree.
      name = "a direct definition of a forwarded scalar fails to evaluate";
      ok = !(builtins.tryEval conflictHost.ghaf.logging.server.endpoint).success;
    }
    {
      name = "org bug-report repo is forwarded into ghaf.services.github in gui-vm";
      ok =
        orgBugReport.repo != null
        && guiVm.ghaf.services.github.owner == orgBugReport.owner
        && guiVm.ghaf.services.github.repo == orgBugReport.repo;
    }
    {
      name = "bug reporter is enabled when an org repo is present";
      ok = guiVm.ghaf.services.github.enable;
    }
    {
      name = "org fleet url is forwarded into ghaf.services.orbit.fleetUrl in gui-vm";
      ok = orgFleetUrl != null && guiVm.ghaf.services.orbit.fleetUrl == orgFleetUrl;
    }
    {
      name = "orbit follows the platform enable once an org fleet url is present";
      ok = guiVm.ghaf.services.orbit.enable == host.ghaf.global-config.orbit.enable;
    }
    {
      name = "org dev-key roster is forwarded into debug SSH on the host";
      ok = orgDevKeys != [ ] && host.ghaf.security.ssh.debug.authorizedKeys == orgDevKeys;
    }
    {
      name = "org user-CA key is forwarded into release SSH on the host";
      ok = shadowHost.ghaf.security.ssh.release.trustedUserCAKeys == [ caTestKey ];
    }
    {
      name = "org user-CA key crosses the wire into a sysvm";
      ok = shadowAdminVm.ghaf.security.ssh.release.trustedUserCAKeys == [ caTestKey ];
    }
    {
      # The forward does not gate on posture, so the option carries the roster
      # everywhere -- this is what keeps the installer ISO reachable.
      name = "the dev-key roster reaches the option on a release image too";
      ok = releaseHost.ghaf.security.ssh.debug.authorizedKeys == orgDevKeys;
    }
    {
      # ...and the consuming module is what keeps it off a release image.
      name = "a release image installs no dev keys for root";
      ok =
        releaseHost.users.users.root.openssh.authorizedKeys.keys == [ ]
        && host.users.users.root.openssh.authorizedKeys.keys == orgDevKeys;
    }
    {
      name = "a direct dev-key definition merges with the org roster";
      ok =
        let
          merged = shadowHost.ghaf.security.ssh.debug.authorizedKeys;
        in
        lib.all (k: lib.elem k merged) orgDevKeys
        && lib.elem extraDevKey merged
        && lib.length merged == lib.length orgDevKeys + 1;
    }
    {
      name = "org AD domain materializes in gui-vm's active-directory config";
      ok =
        orgAd.ad.domain != null
        && guiVm.ghaf.users.active-directory.domains ? ${adName}
        && guiAdDomain.ad.controllers == orgAd.ad.controllers;
    }
    {
      name = "AD realm and LDAP URIs derive from the org domain and controllers";
      ok =
        guiAdDomain.krb5.realm == lib.toUpper orgAd.ad.domain
        && guiAdDomain.ldap.uri == map (c: "ldap://${c}") orgAd.ad.controllers;
    }
    {
      name = "org AD dnsProvider crosses the wire into gui-vm";
      ok = guiAdDomain.dnsProvider.ipAddress == orgAd.dnsProvider.ipAddress;
    }
    {
      name = "the canonical enableSasl default survives the org forward";
      ok = guiAdDomain.ldap.enableSasl;
    }
    {
      # baseDn defaults to null, gpoAccessControl to "permissive": the org
      # forward must leave both undefined, or refining the latter collides
      # with a default the org never chose.
      name = "a direct AD definition merges with the org domain leaf-wise";
      ok =
        shadowAdDomain.ldap.baseDn == "dc=direct"
        && shadowAdDomain.ad.gpoAccessControl == "enforcing"
        && shadowAdDomain.ad.domain == orgAd.ad.domain;
    }
    {
      name = "org firewall-rules url is forwarded into ghaf.firewall.updater.url";
      ok =
        org.network.firewallRulesUrl != null
        && host.ghaf.firewall.updater.url == org.network.firewallRulesUrl;
    }
    {
      name = "an unset org value leaves the module default intact";
      ok = org.network.ntpServers == null && host.ghaf.time.upstreamServers != [ ];
    }
    {
      name = "org NTP servers replace the default pool in a sysvm";
      ok = shadowAdminVm.ghaf.time.upstreamServers == [ "ntp.org-config-test" ];
    }
    {
      name = "org locale and timezone are forwarded on the host";
      ok = shadowHost.i18n.defaultLocale == "de_DE.UTF-8" && shadowHost.time.timeZone == "Asia/Dubai";
    }
    {
      name = "org timezone reaches a sysvm";
      ok = shadowAdminVm.time.timeZone == "Asia/Dubai";
    }
    {
      name = "org admin name and credential are forwarded on the host";
      ok =
        shadowHost.ghaf.users.admin.name == "orgadmin"
        && shadowHost.users.users ? orgadmin
        && shadowHost.ghaf.users.admin.hashedPassword == "org-config-test-hash";
    }
    {
      # userborn prefers hashedPassword, so the org hash already wins; the
      # point of clearing initialPassword is that no plaintext `password` is
      # derived alongside it.
      name = "an org credential leaves no plaintext password beside it";
      ok =
        shadowHost.ghaf.users.admin.initialPassword == null
        && shadowHost.users.users.orgadmin.password == null
        && shadowHost.users.users.orgadmin.hashedPassword == "org-config-test-hash";
    }
    {
      name = "org admin rename crosses the wire into a sysvm";
      ok = shadowAdminVm.ghaf.users.admin.name == "orgadmin" && shadowAdminVm.users.users ? orgadmin;
    }
  ];

  failed = map (a: a.name) (lib.filter (a: !a.ok) assertions);
in
assert lib.assertMsg (failed == [ ]) "org-config delivery: ${lib.concatStringsSep "; " failed}";
runCommand "org-config-delivery" { } ''touch "$out"''
