# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  config,
  lib,
  pkgs,
  ...
}:
let
  # Ghaf systemd config
  cfg = config.ghaf.systemd;

  inherit (lib)
    mkEnableOption
    mkOption
    mkIf
    mkForce
    types
    ;

  # Override minimal systemd package configuration
  package =
    (pkgs.systemdMinimal.override (
      {
        pname = cfg.withName;
        withAcl = true;
        withAnalyze = cfg.withDebug;
        inherit (cfg) withApparmor;
        inherit (cfg) withAudit;
        withCompression = true;
        withCoredump = cfg.withDebug || cfg.withMachines;
        withCryptsetup = cfg.withCryptsetup || cfg.withHomed;
        inherit (cfg) withEfi;
        inherit (cfg) withBootloader;
        inherit (cfg) withFido2;
        withGcrypt = cfg.withJournal; # Required for Forward Secure Sealing (FSS)
        inherit (cfg) withHomed;
        inherit (cfg) withOpenSSL;
        inherit (cfg) withHostnamed;
        withImportd = cfg.withMachines || cfg.withSysupdate;
        withKexectools = cfg.withDebug;
        withKmod = true;
        withLibBPF = true;
        withLibseccomp = true;
        inherit (cfg) withLocaled;
        inherit (cfg) withLogind;
        withMachined = cfg.withMachines || cfg.withNss; # Required for NSS in nixos
        inherit (cfg) withNetworkd;
        inherit (cfg) withNss;
        withOomd = true;
        withPam = true;
        withPasswordQuality = !cfg.withDebug;
        inherit (cfg) withPolkit;
        inherit (cfg) withResolved;
        inherit (cfg) withRepart;
        withShellCompletions = cfg.withDebug;
        withTimedated = true;
        inherit (cfg) withTimesyncd;
        inherit (cfg) withTpm2Tss;
        inherit (cfg) withUkify;
        withVConsole = true;
        withUserDb = cfg.withHomed;
        withUtmp = cfg.withJournal || cfg.withAudit;
        inherit (cfg) withSysupdate;
        inherit (cfg) withHwdb;
      }
      // lib.optionalAttrs (lib.strings.versionAtLeast pkgs.systemdMinimal.version "255.0") {
        withVmspawn = cfg.withMachines;
        withQrencode = true; # Required for systemd-bsod (currently hardcoded in nixos)
      }
    )).overrideAttrs
      (prevAttrs: {
        patches = prevAttrs.patches ++ [
          ./systemd-boot-double-dtb-buffer-size.patch
          ./systemd-re-enable-locale-setting.patch
          ./systemd-localed-locale-archive.patch
        ];
      });

  # Definition of suppressed system units in systemd configuration. This removes the units and has priority.
  # Required to avoid build failures compared to only disabling units for some options. Note that errors will be silently ignored.
  suppressedSystemUnits = [
    ## Default disabled units
    "remote-cryptsetup.service"
    "remote-cryptsetup.target"
    "remote-fs-pre.service"
    "remote-fs-pre.target"
    "remote-fs.service"
    "remote-fs.target"
    "rpcbind.service"
    "rpcbind.target"
    "systemd-update-done.service"
    "system-update.target"
    "system-update-pre.target"
    "system-update-cleanup.service"
    # Factory reset units not included in minimal systemd
    "systemd-tpm2-clear.service"
  ]
  ++ (lib.optionals (!cfg.withMachines) [
    "container-getty.service"
    "container-getty@.service"
    "container@.service"
    "systemd-nspawn@.service"
  ])
  ++ (lib.optionals ((!cfg.withDebug) && (!cfg.withSerial)) [
    "getty.service"
    "getty@.service"
    "getty.target"
    "getty-pre.target"
    "serial-getty.service"
    "serial-getty@.service"
    "serial-getty.target"
    "serial-getty@.target"
  ])
  ++ (lib.optionals ((!cfg.withDebug) && (!cfg.withJournal)) [
    "systemd-journald-audit.socket"
    "systemd-journal-catalog-update.service"
    "systemd-journal-flush.service"
    "systemd-journald.service"
    "systemd-journald@.service"
    "systemd-journal-gatewayd.socket"
    "systemd-journald-audit.socket"
    "systemd-journald-dev-log.socket"
    "systemd-journald-varlink@.socket"
    "systemd-journald.socket"
    "systemd-journald@.socket"
    "systemd-update-utmp.service"
  ])
  ++ (lib.optionals (!cfg.withAudit) [
    "audit.service"
    "auditd.service"
    "systemd-journald-audit.socket"
  ])
  ++ (lib.optionals ((!cfg.withDebug) && (!cfg.withMachines)) [ "systemd-coredump.socket" ])
  ++ (lib.optionals (!cfg.withLogind) [
    "systemd-logind.service"
    "dbus-org.freedesktop.login1.service"
  ])
  ++ (lib.optionals (!cfg.withNss) [
    "nscd.service"
    "nss.service"
    "nss.target"
    "nss-lookup.target"
    "nss-user-lookup.target"
    "nss-lookup.target.requires"
    "nss-user-lookup.target.requires"
  ])
  ++ (lib.optionals (!cfg.withTimesyncd) [ "systemd-timesyncd.service" ])
  ++ (lib.optionals (!cfg.withResolved) [ "systemd-resolved.service" ])
  ++ (lib.optionals (!cfg.withNetworkd) [
    "network.target"
    "network-pre.target"
    "network-online.target"
    "network-interfaces.target"
    "network-setup.service"
    "network-local-commands.service"
    "systemd-timesyncd.service"
    "systemd-networkd-wait-online.service"
    "systemd-networkd.service"
    "systemd-networkd.socket"
  ])
  ++ (lib.optionals (!cfg.withAudio) [
    "sound.target"
  ])
  ++ (lib.optionals (!cfg.withBluetooth) [
    "bluetooth.target"
    "bluetooth.service"
  ])
  ++ (lib.optionals (!cfg.withDebug) [
    ## Units kept with debug
    "kbrequest.target"
    "rescue.service"
    "rescue.target"
    "emergency.service"
    "emergency.target"
    "systemd-vconsole-setup.service"
    "reload-systemd-vconsole-setup.service"
    "console-getty.service"
    "sys-kernel-debug.mount"
    "sys-fs-fuse-connections.mount"
    "systemd-pstore.service"
    "mount-pstore.service"
    "systemd-ask-password-console.path"
    "systemd-ask-password-console.service"
    "systemd-ask-password-wall.path"
    "systemd-ask-password-wall.service"
    "systemd-kexec.service"
    "kexec.service"
    "kexec.target"
    "kexec-tools.service"
    "kexec-tools.target"
    "prepare-kexec.service"
    "prepare-kexec.target"
  ]);
in
{
  _file = ./base.nix;

  options.ghaf.systemd = {
    enable = mkEnableOption "Enable minimal systemd configuration.";

    withName = mkOption {
      description = "Set systemd name.";
      type = types.str;
      default = "base-systemd";
    };

    withLogind = mkOption {
      description = "Enable systemd login daemon.";
      type = types.bool;
      default = true;
    };

    withJournal = mkOption {
      description = "Enable systemd journal daemon.";
      type = types.bool;
      default = true;
    };

    withNetworkd = mkOption {
      description = "Enable systemd networking daemon.";
      type = types.bool;
      default = true;
    };

    withTimesyncd = mkEnableOption "systemd timesync daemon";

    withResolved = mkEnableOption "systemd resolve daemon";

    withRepart = mkEnableOption "systemd repart functionality";

    withHomed = mkEnableOption "systemd homed for users home functionality";

    withHostnamed = mkEnableOption "systemd hostname daemon";

    withNss = mkEnableOption "systemd Name Service Switch (NSS) functionality";

    withEfi = mkOption {
      description = "Enable systemd EFI functionality.";
      type = types.bool;
      default = pkgs.stdenv.hostPlatform.isEfi;
    };

    withBootloader = mkOption {
      description = "Enable systemd bootloader functionality.";
      type = types.bool;
      default = pkgs.stdenv.hostPlatform.isEfi;
    };

    withOpenSSL = mkOption {
      description = "Enable systemd OpenSSL functionality.";
      type = types.bool;
      default = cfg.withFido2 || cfg.withHomed || cfg.withSysupdate;
    };

    withUkify = mkOption {
      description = "Enable systemd UKI functionality.";
      type = types.bool;
      default = pkgs.stdenv.hostPlatform.isEfi;
    };

    withApparmor = mkEnableOption "systemd apparmor functionality";

    withMachines = mkEnableOption "systemd container and VM functionality";

    withAudit = mkEnableOption "systemd audit functionality";

    withCryptsetup = mkEnableOption "systemd LUKS2 functionality";

    withFido2 = mkEnableOption "systemd Fido2 token functionality";

    withTpm2Tss = mkEnableOption "systemd TPM functionality";

    withPolkit = mkEnableOption "systemd polkit functionality";

    withSerial = mkEnableOption "systemd serial console";

    withSysupdate = mkEnableOption "systemd system update functionality";

    withLocaled = mkOption {
      description = "Enable systemd locale daemon.";
      type = types.bool;
      default = true;
    };

    withAudio = mkEnableOption "audio functionality";

    withBluetooth = mkEnableOption "bluetooth functionality";

    withDebug = mkEnableOption "systemd debug functionality";

    withHwdb = mkOption {
      description = "Enable systemd hwdb functionality.";
      type = types.bool;
      default = true;
    };

    logLevel = mkOption {
      description = ''
        Systemd log verbosity. Must be one of 'debug', 'info', 'notice', 'warning', 'err',
        'crit', 'alert', 'emerg'. Defaults to 'info'.
      '';
      type = types.enum [
        "debug"
        "info"
        "notice"
        "warning"
        "err"
        "crit"
        "alert"
        "emerg"
      ];
      default = "info";
    };
  };

  config = mkIf cfg.enable {

    systemd = {
      # Package and unit configuration
      inherit package;
      inherit suppressedSystemUnits;

      # Misc. configurations
      enableEmergencyMode = cfg.withDebug;
      coredump.enable = cfg.withDebug || cfg.withMachines;
      managerEnvironment.SYSTEMD_LOG_LEVEL = cfg.logLevel;
      globalEnvironment.SYSTEMD_LOG_LEVEL = cfg.logLevel;

      # Service startup optimization
      services.systemd-networkd-wait-online.enable = mkForce false;
    };
  };
}
