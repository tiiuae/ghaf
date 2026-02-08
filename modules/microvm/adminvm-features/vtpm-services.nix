# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# Admin VM vTPM Services Feature Module
#
# This module provides swtpm (Software TPM) services in the admin-vm for app VMs
# that have vTPM enabled. It creates:
# - swtpm socket services for each VM with vTPM
# - socat bridge services for vsock communication
#
# This module is auto-included by adminvm-features/default.nix when vTPM VMs exist.
#
{
  lib,
  pkgs,
  hostConfig,
  ...
}:
let
  # Get vTPM-enabled VMs from hostConfig
  appvmConfig = hostConfig.appvms or { };
  vmsWithVtpm = lib.filterAttrs (
    _: vm: (vm.enable or false) && (vm.vtpm.enable or false) && (vm.vtpm.runInVM or false)
  ) appvmConfig;

  makeSwtpmService =
    name: basePort:
    let
      swtpmScript = pkgs.writeShellApplication {
        name = "${name}-swtpm-bin";
        runtimeInputs = with pkgs; [
          coreutils
          swtpm
        ];
        text = ''
          mkdir -p /var/lib/swtpm/${name}/state
          swtpm socket --tpmstate dir=/var/lib/swtpm/${name}/state \
            --ctrl type=tcp,port=${toString basePort} \
            --server type=tcp,port=${toString (basePort + 1)} \
            --tpm2 \
            --log level=20
        '';
      };
    in
    {
      description = "swtpm service for ${name}";
      path = [ swtpmScript ];
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        Type = "exec";
        Restart = "always";
        User = "swtpm_${name}";
        StateDirectory = "swtpm/${name}";
        StateDirectoryMode = "0700";
        StandardOutput = "journal";
        StandardError = "journal";
        ExecStart = lib.getExe swtpmScript;
      };
    };

  makeSocatService =
    name: channel: port:
    let
      socatScript = pkgs.writeShellApplication {
        name = "${name}-socat";
        runtimeInputs = with pkgs; [
          socat
        ];
        text = ''
          socat VSOCK-LISTEN:${toString port},fork TCP:127.0.0.1:${toString port}
        '';
      };
    in
    {
      description = "socat ${channel} channel for ${name}";
      path = [ socatScript ];
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        Type = "simple";
        Restart = "always";
        DynamicUser = "on";
        StandardOutput = "journal";
        StandardError = "journal";
        ExecStart = lib.getExe socatScript;
      };
    };

  makeSwtpmInstanceConfig = name: vm: {
    users.users."swtpm_${name}" = {
      isSystemUser = true;
      home = "/var/lib/swtpm/${name}";
      group = "swtpm_${name}";
    };
    users.groups."swtpm_${name}" = { };

    systemd.services = {
      "${name}-swtpm" = makeSwtpmService name vm.vtpm.basePort;
      "${name}-socat-control" = makeSocatService name "control" vm.vtpm.basePort;
      "${name}-socat-data" = makeSocatService name "data" (vm.vtpm.basePort + 1);
    };
  };

  configs = lib.mapAttrsToList makeSwtpmInstanceConfig vmsWithVtpm;
in
{
  _file = ./vtpm-services.nix;

  config = lib.foldr lib.recursiveUpdate { } configs;
}
