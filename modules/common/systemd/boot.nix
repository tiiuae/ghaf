# Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  config,
  lib,
  pkgs,
  ...
}: let
  # Ghaf configuration flags
  cfg = config.ghaf.systemd.boot;
  cfgBase = config.ghaf.systemd;

  # Package configuration
  package = pkgs.systemdMinimal.override {
    pname = "stage1-systemd";
    inherit (cfgBase) withAudit;
    inherit (cfgBase) withCryptsetup;
    inherit (cfgBase) withEfi;
    inherit (cfgBase) withFido2;
    inherit (cfgBase) withRepart;
    inherit (cfgBase) withTpm2Tss;
  };

  # Suppressed initrd systemd units
  suppressedUnits =
    [
      "multi-user.target"
    ]
    ++ (lib.optionals ((!cfgBase.withDebug) && (!cfgBase.withJournal)) [
      "systemd-journald.service"
      "systemd-journald.socket"
      "systemd-journald-dev-log.socket"
    ])
    ++ (lib.optionals ((!cfgBase.withDebug) && (!cfgBase.withAudit)) [
      "systemd-journald-audit.socket"
    ])
    ++ (lib.optionals (!cfgBase.withDebug) [
      "kexec.target"
      "systemd-kexec.service"
      "emergency.service"
      "emergency.target"
      "rescue.service"
      "rescue.target"
      "rpcbind.target"
    ]);
in
  with lib; {
    options.ghaf.systemd.boot = {
      enable = mkEnableOption "Enable systemd in stage 1 of the boot (initrd).";
    };

    config = mkIf cfg.enable {
      boot.initrd = {
        verbose = config.ghaf.profiles.debug.enable;
        services.lvm.enable = true;
        systemd = {
          enable = true;
          inherit package;
          inherit suppressedUnits;
          emergencyAccess = config.ghaf.profiles.debug.enable;
          enableTpm2 = cfgBase.withTpm2Tss;
          initrdBin = optionals config.ghaf.profiles.debug.enable [pkgs.lvm2 pkgs.util-linux];
        };
      };
    };
  }
