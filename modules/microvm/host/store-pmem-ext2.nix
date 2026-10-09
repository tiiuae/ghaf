# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# Keeps the pmem-ext2 image caches of the crosvm guests in /persist/ghaf-store.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.ghaf.virtualization.microvm-host;
  dir = "/persist/ghaf-store";

  cacheOf =
    vmEntry:
    let
      vmConfig = lib.ghaf.vm.getConfig vmEntry;
      arg = lib.findFirst (lib.hasInfix ":cache=") null (vmConfig.microvm.crosvm.extraArgs or [ ]);
    in
    if vmConfig == null || arg == null then null else lib.last (lib.splitString ":cache=" arg);

  caches = lib.filterAttrs (_: c: c != null) (lib.mapAttrs (_: cacheOf) config.microvm.vms);
in
{
  _file = ./store-pmem-ext2.nix;

  config = lib.mkIf (cfg.enable && caches != { }) {
    systemd.tmpfiles.rules = [ "d ${dir} 0700 microvm kvm -" ];

    systemd.services = lib.mapAttrs' (
      name: cache:
      lib.nameValuePair "microvm@${name}" {
        serviceConfig.ExecStartPre = [
          "${lib.getExe pkgs.findutils} ${dir} -maxdepth 1 -regextype egrep -regex '.*/${name}-[0-9a-f]{64}[.]zst([.]tmp)?' ! -path ${cache} -delete"
        ];
      }
    ) caches;
  };
}
