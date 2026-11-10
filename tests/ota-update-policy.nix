# SPDX-FileCopyrightText: 2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  self,
  lib,
  runCommand,
  ota-update,
  ota-update-debug,
}:
let
  host = name: self.nixosConfigurations.${name}.config;
  release = host "intel-laptop-release";
  debug = host "intel-laptop-debug";
  verity = host "intel-laptop-debug-secure-ab";
  guiRules = c: c.microvm.vms.gui-vm.evaluatedConfig.config.ghaf.givc.accessControl.adminRules;
  permitsClosureUpdates =
    c: lib.any (rule: lib.elem "SetGeneration" rule.permittedRequests) (guiRules c);
  updaterInPath =
    c: package: lib.any (p: toString p == toString package) c.systemd.services.givc-ghaf-host.path;
in
assert !release.givc.host.closureUpdates;
assert !verity.givc.host.closureUpdates;
assert debug.givc.host.closureUpdates;
assert !permitsClosureUpdates release;
assert permitsClosureUpdates debug;
assert updaterInPath release ota-update;
assert updaterInPath verity ota-update;
assert updaterInPath debug ota-update-debug;
runCommand "ota-update-policy" { } ''touch "$out"''
