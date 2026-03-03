# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.ghaf.virtualization.microvm-host.tpmMux;
  muxedVms = lib.attrNames (
    lib.filterAttrs (
      _name: vm: (vm.config.ghaf.virtualization.microvm.tpm.muxed.enable or false)
    ) config.microvm.vms
  );
  forwarderVms = if cfg.vms == [ ] then muxedVms else cfg.vms;
  inherit (lib)
    mkEnableOption
    mkIf
    mkMerge
    mkOption
    types
    ;
in
{
  _file = ./tpm-mux.nix;

  options.ghaf.virtualization.microvm-host.tpmMux = {
    enable = mkEnableOption "host TPM mux scaffold with abrmd and per-VM forwarders";

    vms = mkOption {
      type = types.listOf types.str;
      default = [ ];
      description = "VM names to provision TPM forwarder instances for";
    };

    runDir = mkOption {
      type = types.str;
      default = "/run/ghaf-vtpm";
      description = "Runtime directory for per-VM TPM link paths";
    };

    backendDevice = mkOption {
      type = types.str;
      default = "/dev/tpmrm0";
      description = "Host TPM device that forwarder links to";
    };
  };

  config = mkMerge [
    {
      ghaf.virtualization.microvm-host.tpmMux.enable = lib.mkDefault (forwarderVms != [ ]);
    }
    (mkIf cfg.enable {
      security.tpm2 = {
        enable = true;
        abrmd.enable = lib.mkForce true;
      };

      boot.kernelModules = [ "tpm_vtpm_proxy" ];

      systemd.tmpfiles.rules = [ "d ${cfg.runDir} 0755 root root -" ];

      systemd.services =
        (lib.listToAttrs (
          map (vmName: {
            name = "ghaf-vtpm-forwarder-${vmName}";
            value = {
              description = "TPM mux forwarder for ${vmName}";
              wantedBy = [ "microvms.target" ];
              before = [ "microvm@${vmName}.service" ];
              wants = [ "tpm2-abrmd.service" ];
              after = [ "tpm2-abrmd.service" ];
              serviceConfig = {
                Type = "notify";
                NotifyAccess = "main";
                TimeoutStartSec = "45s";
                Restart = "always";
                RestartSec = "1s";
                ExecStart = "${pkgs.vtpm-abrmd-forwarder}/bin/vtpm-abrmd-forwarder --vm-name ${vmName} --backend-device ${cfg.backendDevice} --link-path ${cfg.runDir}/${vmName}.tpm";
              };
            };
          }) forwarderVms
        ))
        // (lib.listToAttrs (
          map (vmName: {
            name = "microvm@${vmName}";
            value = {
              requires = [ "ghaf-vtpm-forwarder-${vmName}.service" ];
              after = [ "ghaf-vtpm-forwarder-${vmName}.service" ];
            };
          }) forwarderVms
        ));
    })
  ];
}
