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

  adminVm = host.microvm.vms."admin-vm".evaluatedConfig.config;
  appVm = host.microvm.vms."flatpak-vm".evaluatedConfig.config;
  guiVm = host.microvm.vms."gui-vm".evaluatedConfig.config;

  org = host.ghaf.org;
  orgEndpoint = org.telemetry.logging.endpoint;
  orgServerName = org.telemetry.logging.serverName;
  orgBugReport = org.telemetry.bugReport;

  # An override through ghaf.org must reach the host and every VM. mkForce
  # because the value overridden here is one tii.nix already sets; an org value
  # the reference leaves unset needs no priority. The same extended host carries
  # an org user-CA key (TII sets none in-tree) to prove list-valued release-SSH
  # material crosses the wire, an org admin credential to prove the hash
  # actually reaches the user, and a direct partial definition of the org's AD
  # domain to prove submodule-valued org data merges leaf-wise.
  overridden = "https://override.example/loki/api/v1/push";
  revokedPeerKey = "spki-sha256:0000000000000000000000000000000000000000000000000000000000000000";
  shadowHost =
    (self.nixosConfigurations.intel-laptop-debug.extendModules {
      modules = [
        {
          _file = "org-config-test-shadow";
          ghaf.org = {
            telemetry.logging.endpoint = lib.mkForce overridden;
            telemetry.logging.logseald.revokedPeerKeys = [ revokedPeerKey ];
          };
        }
      ];
    }).config;
  shadowAdminVm = shadowHost.microvm.vms."admin-vm".evaluatedConfig.config;

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
  ];

  failed = map (a: a.name) (lib.filter (a: !a.ok) assertions);
in
assert lib.assertMsg (failed == [ ]) "org-config delivery: ${lib.concatStringsSep "; " failed}";
runCommand "org-config-delivery" { } ''touch "$out"''
