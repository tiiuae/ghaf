# Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  lib,
  config,
  pkgs,
  ...
}: let
  hugepagesz = 2;
  hugepages = config.ghaf.profiles.applications.ivShMemServer.memSize / hugepagesz;
in {
  config = lib.mkIf config.ghaf.profiles.applications.ivShMemServer.enable {
    boot.kernelParams = [
      "hugepagesz=${toString hugepagesz}M"
      "hugepages=${toString hugepages}"
    ];
    systemd.services = {
      ivshmemsrv = let
        socketPath = config.ghaf.profiles.applications.ivShMemServer.hostSocketPath;
        pidFilePath = "/tmp/ivshmem-server.pid";
        ivShMemSrv = let
          vectors = toString (2 * config.ghaf.profiles.applications.ivShMemServer.vmCount);
        in
          pkgs.writeShellScriptBin "ivshmemsrv" ''
            chown microvm /dev/hugepages
            chgrp kvm /dev/hugepages
            if [ -S ${socketPath} ]; then
              echo Erasing ${socketPath} ${pidFilePath}
              rm -f ${socketPath}
            fi
            ${pkgs.sudo}/sbin/sudo -u microvm -g kvm ${pkgs.qemu_kvm}/bin/ivshmem-server -p ${pidFilePath} -n ${vectors} -m /dev/hugepages/ -l ${(toString config.ghaf.profiles.applications.ivShMemServer.memSize) + "M"}
            sleep 2
          '';
      in
        lib.mkIf config.ghaf.profiles.applications.ivShMemServer.enable {
          enable = true;
          description = "Start qemu ivshmem memory server";
          path = [ivShMemSrv];
          wantedBy = ["multi-user.target"];
          serviceConfig = {
            Type = "oneshot";
            RemainAfterExit = true;
            StandardOutput = "journal";
            StandardError = "journal";
            ExecStart = "${ivShMemSrv}/bin/ivshmemsrv";
          };
        };
    };
  };
}
