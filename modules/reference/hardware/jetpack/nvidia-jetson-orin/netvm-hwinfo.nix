# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{ lib, ... }:
{
  _file = ./netvm-hwinfo.nix;

  imports = [ ../../../../common/services/hwinfo ];

  ghaf = {
    services.hwinfo = {
      enable = true;
      outputDir = "/var/lib/ghaf-hwinfo";
    };

    hardware.definition.netvm.extraModules = [
      (
        { config, ... }:
        let
          useCrosvm = config.microvm.hypervisor == "crosvm";
        in
        {
          imports = [ ../../../../common/services/hwinfo ];

          ghaf.services.hwinfo-guest = {
            enable = true;
            filePath = lib.mkIf useCrosvm "/run/ghaf-hwinfo/hwinfo.json";
          };

          microvm = {
            shares = lib.optionals useCrosvm [
              {
                tag = "ghaf-hwinfo";
                source = "/var/lib/ghaf-hwinfo";
                mountPoint = "/run/ghaf-hwinfo";
                proto = "virtiofs";
                readOnly = true;
              }
            ];
            qemu.extraArgs = lib.mkIf (!useCrosvm) [
              "-fw_cfg"
              "name=opt/com.ghaf.hwinfo,file=/var/lib/ghaf-hwinfo/hwinfo.json"
            ];
          };
        }
      )
    ];
  };

  systemd.services."microvm@net-vm" = {
    wants = [ "ghaf-hwinfo-generate.service" ];
    after = [ "ghaf-hwinfo-generate.service" ];
  };
}
