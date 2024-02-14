# Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  config,
  lib,
  pkgs,
  ...
}: let
  # Ghaf configuration
  cfg = config.ghaf.systemd;

  # Override minimal systemd package configuration
  package =
    pkgs.systemdMinimal.override {
      pname = cfg.withName;
      withAcl = true;
      withAnalyze = cfg.withDebug;
      inherit (cfg) withApparmor;
      inherit (cfg) withAudit;
      withCompression = true;
      withCoredump = cfg.withDebug || cfg.withVirtualization;
      inherit (cfg) withCryptsetup; # also enables PKCS#11 support
      inherit (cfg) withEfi; # withEfi also controls 'withBootloader' (compiles systemd-boot)
      withBootloader = cfg.withEfi; # but for some reason it fails if not explicity set
      inherit (cfg) withFido2;
      withImportd = cfg.withVirtualization;
      withKexectools = false;
      withKmod = true;
      withLibBPF = true;
      withLibseccomp = true;
      inherit (cfg) withLocaled;
      inherit (cfg) withLogind;
      withMachined = cfg.withVirtualization;
      inherit (cfg) withNetworkd;
      inherit (cfg) withNss;
      withOomd = true;
      withPam = true;
      inherit (cfg) withPolkit;
      withResolved = cfg.withNetworkd || cfg.withNss;
      withSelinux = false;
      withShellCompletions = cfg.withDebug;
      withTimedated = true;
      withTimesyncd = cfg.withNetworkd;
      inherit (cfg) withTpm2Tss;
      withUtmp = cfg.withJournal || cfg.withAudit;
    }
    // lib.optionalAttrs (lib.hasAttr "withVmspawn" (lib.functionArgs pkgs.systemd.override)) {
      withVmspawn = cfg.withVirtualization;
    };

  # Definition of suppressed system units in systemd configuration. This removes the units and has priority.
  # Required to avoid build failures when only disabling the units, and removes unit files.
  # Note that errors will be silently ignored.
  suppressedSystemUnits =
    [
      ## Default disabled units
      "systemd-kexec.service"
      "kexec.service"
      "kexec.target"
      "kexec-tools.service"
      "kexec-tools.target"
      "prepare-kexec.service"
      "prepare-kexec.target"
      "remote-cryptsetup.service"
      "remote-cryptsetup.target"
      "remote-fs-pre.service"
      "remote-fs-pre.target"
      "remote-fs.service"
      "remote-fs.target"
      "rpcbind.service"
      "rpcbind.target"
      "systemd-ask-password-console.path"
      "systemd-ask-password-console.service"
      "systemd-ask-password-wall.path"
      "systemd-ask-password-wall.service"
      "systemd-update-done.service"
      "system-update.target"
      "system-update-pre.target"
      "system-update-cleanup.service"
    ]
    ++ (lib.optionals (!cfg.withVirtualization) [
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
    ++ (lib.optionals ((!cfg.withDebug) && (!cfg.withVirtualization)) [
      "systemd-coredump.socket"
    ])
    ++ (lib.optionals (!cfg.withLogind) [
      "systemd-logind.service"
      "dbus-org.freedesktop.login1.service"
    ])
    ++ (lib.optionals (!cfg.withNss) [
      "nss.service"
      "nss.target"
      "nss-lookup.target"
      "nss-user-lookup.target"
      "nss-lookup.target.requires"
      "nss-user-lookup.target.requires"
    ])
    ++ (lib.optionals (!cfg.withPrinter) [
      "cups.service"
      "cups.target"
      "cups.socket"
      "cups-lpd.socket"
      "cups-lpd@.service"
      "cups-browsed.service"
      "cups-browsed.target"
      "printer.service"
      "printer.target"
    ])
    ++ (lib.optionals (!cfg.withNetworkd) [
      "network.target"
      "network-pre.target"
      "network-online.target"
      "network-interfaces.target"
      "network-setup.service"
      "network-local-commands.service"
      "systemd-timesyncd.service"
      "systemd-resolved.service"
      "systemd-networkd-wait-online.service"
      "systemd-networkd.service"
      "systemd-networkd.socket"
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
    ]);
in
  with lib; {
    options.ghaf.systemd = {
      enable = mkOption {
        description = "Enable minimal systemd configuration.";
        type = types.bool;
        default = true;
      };

      withName = mkOption {
        description = "Set systemd derivation name.";
        type = types.str;
        default = "base-systemd";
      };

      withApparmor = mkOption {
        description = "Enable systemd apparmor functionality.";
        type = types.bool;
        default = true;
      };

      withLogind = mkOption {
        description = "Enable systemd logind functionality.";
        type = types.bool;
        default = true;
      };

      withJournal = mkOption {
        description = "Enable systemd journal functionality.";
        type = types.bool;
        default = true;
      };

      withNetworkd = mkOption {
        description = "Enable systemd networking functionality.";
        type = types.bool;
        default = true;
      };

      withEfi = mkOption {
        description = "Enable systemd EFI+bootloader functionality.";
        type = types.bool;
        default = pkgs.stdenv.hostPlatform.isEfi;
      };

      withVirtualization = mkOption {
        description = "Enable systemd container and VM functionality.";
        type = types.bool;
        default = false;
      };

      withAudit = mkOption {
        description = "Enable systemd audit functionality.";
        type = types.bool;
        default = false;
      };

      withNss = mkOption {
        description = "Enable systemd Name Service Switch (NSS) functionality.";
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

      withPrinter = mkOption {
        description = "Enable systemd printer functionality.";
        type = types.bool;
        default = false;
      };

      withLocaled = mkOption {
        description = "Enable systemd localed functionality.";
        type = types.bool;
        default = false;
      };

      withDebug = mkOption {
        description = "Enable systemd debug functionality.";
        type = types.bool;
        default = config.ghaf.profiles.debug.enable;
      };
    };

    config = mkIf cfg.enable {
      systemd = {
        # Package and unit configuration
        inherit package;
        inherit suppressedSystemUnits;

        # Misc. configurations
        enableEmergencyMode = cfg.withDebug;
        coredump.enable = cfg.withDebug || cfg.withVirtualization;
      };
    };
  }
