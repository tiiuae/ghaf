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

    withTimesyncd = mkOption {
      description = "Enable systemd timesync daemon.";
      type = types.bool;
      default = false;
    };

    withResolved = mkOption {
      description = "Enable systemd resolve daemon.";
      type = types.bool;
      default = false;
    };

    withRepart = mkOption {
      description = "Enable systemd repart functionality.";
      type = types.bool;
      default = false;
    };

    withHomed = mkOption {
      description = "Enable systemd homed for users home functionality.";
      type = types.bool;
      default = false;
    };

    withHostnamed = mkOption {
      description = "Enable systemd hostname daemon.";
      type = types.bool;
      default = false;
    };

    withNss = mkOption {
      description = "Enable systemd Name Service Switch (NSS) functionality.";
      type = types.bool;
      default = false;
    };

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

    withApparmor = mkOption {
      description = "Enable systemd apparmor functionality.";
      type = types.bool;
      default = false;
    };

    withMachines = mkOption {
      description = "Enable systemd container and VM functionality.";
      type = types.bool;
      default = false;
    };

    withAudit = mkOption {
      description = "Enable systemd audit functionality.";
      type = types.bool;
      default = false;
    };

    withCryptsetup = mkOption {
      description = "Enable systemd LUKS2 functionality.";
      type = types.bool;
      default = false;
    };

    withFido2 = mkOption {
      description = "Enable systemd Fido2 token functionality.";
      type = types.bool;
      default = false;
    };

    withTpm2Tss = mkOption {
      description = "Enable systemd TPM functionality.";
      type = types.bool;
      default = false;
    };

    withPolkit = mkOption {
      description = "Enable systemd polkit functionality.";
      type = types.bool;
      default = false;
    };

    withSerial = mkOption {
      description = "Enable systemd serial console.";
      type = types.bool;
      default = false;
    };

    withSysupdate = mkOption {
      description = "Enable systemd system update functionality.";
      type = types.bool;
      default = false;
    };

    withLocaled = mkOption {
      description = "Enable systemd locale daemon.";
      type = types.bool;
      default = true;
    };

    withAudio = mkOption {
      description = "Enable audio functionality.";
      type = types.bool;
      default = false;
    };

    withBluetooth = mkOption {
      description = "Enable bluetooth functionality.";
      type = types.bool;
      default = false;
    };

    withDebug = mkOption {
      description = "Enable systemd debug functionality.";
      type = types.bool;
      default = false;
    };

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
