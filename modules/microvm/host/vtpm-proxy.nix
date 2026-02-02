# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.ghaf.virtualization.microvm.appvm;

  vms = lib.filterAttrs (_: vm: vm.enable) cfg.vms;
  vmsWithVtpm = lib.filterAttrs (_name: vm: vm.vtpm.enable && vm.vtpm.runInVM) vms;
in
lib.mkIf cfg.enable {
  # Spawn a swtpm-proxy on the host for each VM with vtpm enabled
  systemd.services =
    let
      mkSwtpmProxyService = name: cport: {
        description = "swtpm proxy for ${name}";

        # admin-vm is hard-coded to host the vTPM daemons
        script = ''
          ${pkgs.swtpm-proxy-shim}/bin/swtpm-proxy --type vsock \
            --control-port ${toString cport} \
            --control-retry-count 30 \
            /var/lib/microvms/${name}-vm/vtpm.sock \
            ${toString config.ghaf.networking.hosts.admin-vm.cid}
        '';

        serviceConfig = {
          Type = "exec";
          Restart = "always";
          User = "microvm";
          Slice = "system-appvms-${name}.slice";
        };
        wantedBy = [ "microvms.target" ];
        before = [ "microvm@${name}-vm.service" ];
        after = [ "microvm@admin-vm.service" ];
        wants = [ "microvm@admin-vm.service" ];
      };
    in
    lib.mapAttrs' (
      name: vm:
      lib.attrsets.nameValuePair "swtpm-proxy-${name}" (mkSwtpmProxyService name vm.vtpm.basePort)
    ) vmsWithVtpm;

  # Launch swtpm processes in admin VM - uses extensions registry
  ghaf.virtualization.microvm.extensions.adminvm = [
    (
      { lib, pkgs, ... }:
      let
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
      lib.foldr lib.recursiveUpdate { } configs
    )
  ];
}
