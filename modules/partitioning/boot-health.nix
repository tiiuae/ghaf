# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.ghaf.boot-health;
  vmNames =
    (lib.attrNames config.microvm.vms)
    ++ lib.optional (cfg.debugUnhealthyMicrovm != null) cfg.debugUnhealthyMicrovm;
  vmServices = map (name: "microvm@${name}.service") vmNames;
  health = pkgs.writeShellApplication {
    name = "ghaf-boot-health";
    runtimeInputs = with pkgs; [
      coreutils
      cryptsetup
      util-linux
      systemd
    ];
    text = ''
      set -euo pipefail

      bootctl=${pkgs.systemd}/bin/bootctl
      bless_boot=${pkgs.systemd}/lib/systemd/systemd-bless-boot
      boot_status="$($bless_boot status 2>/dev/null || true)"
      current_stub=""
      while IFS= read -r status_line; do
        if [[ "$status_line" == *"/EFI/Linux/"* ]]; then
          current_stub="''${status_line##*/EFI/Linux/}"
          break
        fi
      done < <("$bootctl" status --no-pager 2>/dev/null || true)

      trial_boot=false
      trial_entry=""
      trial_tries_left=""
      # Once the final try has been consumed, systemd-bless-boot no longer
      # reports "indeterminate", but the currently executing UKI still has
      # its boot-counting suffix (for example +0-3.efi).  It remains a failed
      # trial and must reboot so systemd-boot can select the blessed fallback.
      if [[ "$current_stub" =~ ^(.+)\+([0-9]+)(-[0-9]+)?\.efi$ ]]; then
        trial_boot=true
        trial_entry="''${BASH_REMATCH[1]}.efi"
        trial_tries_left="''${BASH_REMATCH[2]}"
      elif [[ "$boot_status" == "indeterminate" ]]; then
        # Fail closed if systemd reports a trial but bootctl does not expose a
        # parseable counter. Rebooting here could consume the fallback early.
        trial_boot=true
      fi

      fail() {
        echo "ghaf-boot-health: $*" >&2
        if $trial_boot; then
          if [[ -z "$trial_entry" || -z "$trial_tries_left" ]]; then
            echo "ghaf-boot-health: cannot safely identify the current trial entry" >&2
            exit 1
          fi
          # LoaderEntryOneShot is consumed when an attempt starts. Re-arm the
          # same entry while tries remain; after +0, leave the persistent
          # blessed default untouched so the reboot selects the fallback.
          if (( trial_tries_left > 0 )); then
            "$bootctl" set-oneshot "$trial_entry" || {
              echo "ghaf-boot-health: could not schedule the next trial attempt" >&2
              exit 1
            }
          fi
          systemctl reboot --message="Ghaf A/B trial health check failed: $*"
        fi
        exit 1
      }

      cryptsetup status ${lib.escapeShellArg cfg.luksMapper} >/dev/null \
        || fail "LUKS mapping ${cfg.luksMapper} is not active"
      veritysetup status ${lib.escapeShellArg cfg.verityMapper} >/dev/null \
        || fail "verity mapping ${cfg.verityMapper} is not active"
      findmnt --mountpoint /nix/store >/dev/null || fail "/nix/store is not mounted"
      findmnt --mountpoint /persist >/dev/null || fail "/persist is not mounted"
      ${lib.concatMapStringsSep "\n" (service: ''
        systemctl is-active --quiet ${lib.escapeShellArg service} \
          || fail "core VM service ${service} is not active"
      '') vmServices}

      generation=""
      read -r -a kernel_cmdline < /proc/cmdline
      for arg in "''${kernel_cmdline[@]}"; do
        case "$arg" in ghaf.generation=*) generation="''${arg#*=}" ;; esac
      done
      [[ "$generation" =~ ^[1-9][0-9]*$ ]] || fail "missing or invalid ghaf.generation"

      accepted=${lib.escapeShellArg cfg.acceptedGenerationFile}
      accepted_generation=0
      if [[ -e "$accepted" ]]; then
        read -r accepted_generation < "$accepted"
        [[ "$accepted_generation" =~ ^[1-9][0-9]*$ ]] \
          || fail "accepted generation state is invalid"
      fi

      if (( generation < accepted_generation )); then
        echo "ghaf-boot-health: healthy fallback generation $generation; accepted generation remains $accepted_generation"
        exit 0
      fi
      if (( generation == accepted_generation )); then
        echo "ghaf-boot-health: generation $generation remains healthy"
        exit 0
      fi

      if $trial_boot; then
        "$bless_boot" good \
          || fail "systemd could not bless the trial boot"
      fi

      current_entry="$current_stub"
      if [[ "$current_entry" =~ ^(.+)\+[0-9]+(-[0-9]+)?\.efi$ ]]; then
        current_entry="''${BASH_REMATCH[1]}.efi"
      fi
      [[ "$current_entry" == *.efi ]] || {
        echo "ghaf-boot-health: cannot identify the healthy boot entry" >&2
        exit 1
      }
      "$bootctl" set-default "$current_entry" || {
        echo "ghaf-boot-health: could not promote the healthy boot entry" >&2
        exit 1
      }

      install -d -m 0700 "$(dirname "$accepted")"
      printf '%s\n' "$generation" > "$accepted.tmp"
      chmod 0600 "$accepted.tmp"
      sync -f "$accepted.tmp"
      mv "$accepted.tmp" "$accepted"
      sync -f "$(dirname "$accepted")"
      echo "ghaf-boot-health: generation $generation accepted"
    '';
  };
in
{
  options.ghaf.boot-health = {
    enable = lib.mkEnableOption "health-gated systemd-boot A/B trial blessing";
    luksMapper = lib.mkOption {
      type = lib.types.str;
      default = config.ghaf.hardware.nvidia.orin.diskEncryption.mapperName;
    };
    verityMapper = lib.mkOption {
      type = lib.types.str;
      default = "nix-store";
    };
    acceptedGenerationFile = lib.mkOption {
      type = lib.types.str;
      default = "/persist/common/ota/accepted-generation";
    };
    debugUnhealthyMicrovm = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = ''
        Debug-only nonexistent MicroVM name used to exercise trial-boot rollback.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = cfg.debugUnhealthyMicrovm == null || config.ghaf.profiles.debug.enable;
        message = "ghaf.boot-health.debugUnhealthyMicrovm is restricted to debug images";
      }
    ];
    # The generic systemd service blesses solely on reaching boot-complete.
    # Ghaf needs the stricter storage and MicroVM health gate above.
    systemd.services.systemd-bless-boot.enable = false;
    systemd.services.ghaf-boot-health = {
      description = "Validate and bless a Ghaf A/B trial boot";
      wantedBy = [ "multi-user.target" ];
      after = [
        "cryptsetup.target"
        "persist.mount"
        "microvms.target"
      ]
      ++ vmServices;
      wants = [
        "persist.mount"
        "microvms.target"
      ]
      ++ vmServices;
      serviceConfig = {
        Type = "oneshot";
        ExecStart = lib.getExe health;
        TimeoutStartSec = "10min";
      };
    };
    environment.systemPackages = [ health ];
  };
}
