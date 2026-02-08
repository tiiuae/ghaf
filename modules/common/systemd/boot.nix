# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  config,
  lib,
  pkgs,
  ...
}:
let
  # Ghaf configuration flags
  cfg = config.ghaf.systemd.boot;
  cfgBase = config.ghaf.systemd;

  inherit (lib)
    mkIf
    optionals
    mkOption
    ;

  # Package configuration
  package = pkgs.systemdMinimal.override (
    {
      pname = "stage1-systemd";
      inherit (cfgBase) withAudit;
      inherit (cfgBase) withBootloader;
      inherit (cfgBase) withCryptsetup;
      inherit (cfgBase) withEfi;
      inherit (cfgBase) withFido2;
      inherit (cfgBase) withLocaled;
      inherit (cfgBase) withRepart;
      inherit (cfgBase) withTpm2Tss;
      inherit (cfgBase) withUkify;
      inherit (cfgBase) withOpenSSL;
      withVConsole = true;
    }
    // lib.optionalAttrs (lib.strings.versionAtLeast pkgs.systemdMinimal.version "255.0") {
      withQrencode = true; # Required for systemd-bsod, which is currently hardcoded in nixos
    }
  );

  # Suppressed initrd systemd units
  suppressedUnits =
    (lib.optionals ((!cfgBase.withDebug) && (!cfgBase.withJournal)) [
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
      "systemd-vconsole-setup.service"
    ]);
in
{
  _file = ./boot.nix;

  options.ghaf.systemd.boot = {
    enable = mkOption {
      default = config.ghaf.systemd.enable;
      description = "Enable systemd in stage 1 of the boot (initrd).";
    };
  };

  config = mkIf cfg.enable {
    boot.initrd = {
      services.lvm.enable = true;
      systemd = {
        enable = true;
        inherit package;
        inherit suppressedUnits;
        emergencyAccess = cfgBase.withDebug;
        tpm2.enable = cfgBase.withTpm2Tss;
        initrdBin = optionals cfgBase.withDebug [
          pkgs.lvm2
          pkgs.util-linux
        ];
        managerEnvironment.SYSTEMD_LOG_LEVEL = cfgBase.logLevel;
      };
    };
  };
}
