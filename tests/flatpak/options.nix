# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# VM-free check for ghaf.reference.appvms.flatpak.{remotes,store.enable}.
# Evaluates the real app VM rather than a stub, so the GIVC ids it asserts are
# the ones a caller would actually address.
{
  self,
  lib,
  runCommand,
}:
let
  vmWith =
    cfg:
    (self.nixosConfigurations.intel-laptop-debug.extendModules {
      modules = [ { ghaf.reference.appvms.flatpak = cfg; } ];
    }).config.microvm.vms.flatpak-vm.evaluatedConfig.config;

  default = vmWith { };
  offline = vmWith {
    remotes = [ ];
    store.enable = false;
  };
  localOnly = vmWith {
    remotes = [
      {
        name = "local";
        url = "file:///mnt/ssd/repo";
        gpgVerify = false;
      }
    ];
  };

  ids = vm: map (app: app.name) vm.ghaf.givc.appvm.applications;
  script = vm: vm.systemd.services.flatpak-repo.script;

  # GIVC derives these from desktopName, not name, so they are what a caller
  # addresses and must not move when the store entry goes.
  managerIds = [
    "run-flatpak-app"
    "uninstall-flatpak-app"
    "kill-flatpak-app"
  ];

  assertions = [
    {
      name = "default keeps the app store entry";
      ok = ids default == [ "app-store" ] ++ managerIds;
    }
    {
      name = "default registers flathub";
      ok = lib.hasInfix "flathub https://flathub.org/repo/flathub.flatpakrepo" (script default);
    }
    {
      name = "default waits for the network";
      ok = default.systemd.services.flatpak-repo.after == [ "network-online.target" ];
    }
    {
      name = "no remotes generates no unit at all";
      ok = !(offline.systemd.services ? flatpak-repo);
    }
    {
      name = "dropping the store leaves the manager givc ids alone";
      ok = ids offline == managerIds;
    }
    {
      name = "an unsigned local remote skips gpg verification";
      ok = lib.hasInfix "--no-gpg-verify local file:///mnt/ssd/repo" (script localOnly);
    }
    {
      name = "a file:// remote does not wait for the network";
      ok = localOnly.systemd.services.flatpak-repo.after == [ ];
    }
  ];

  failed = map (a: a.name) (lib.filter (a: !a.ok) assertions);
in
assert lib.assertMsg (failed == [ ]) "flatpak options: ${lib.concatStringsSep "; " failed}";
runCommand "flatpak-options" { } ''touch "$out"''
