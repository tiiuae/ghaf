# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  config,
  lib,
  pkgs,
  ...
}:
let
  inherit (lib)
    mkIf
    mkOption
    types
    ;

  cfg = config.ghaf.services.sysinfo;

  ghafSysinfo = pkgs.writeShellApplication {
    name = "ghaf-sysinfo";
    runtimeInputs = with pkgs; [
      coreutils
      systemd
      gnugrep
      util-linux
    ];
    text = ''
      export PATH=/run/wrappers/bin:/run/current-system/sw/bin
      json_output=false
      if [ "''${1:-}" = "--json" ]; then
        json_output=true
      fi

      # This app used to extract and display key system information relevant to Ghaf, such as the Ghaf version, secure boot status and disk encryption status.
      # It is designed to be simple and provide a quick overview of the system's security posture.

      ghaf_version="Unknown"
      if command -v ghaf-version >/dev/null 2>&1; then
        ghaf_version="$(ghaf-version 2>/dev/null | head -n1 | xargs)"
        [ -n "$ghaf_version" ] || ghaf_version="Unknown"
      fi

      secure_boot="Unknown"
      bootctl_output="$(bootctl status 2>/dev/null || true)"
      secure_boot_raw="$(printf '%s\n' "$bootctl_output" | grep -E '^[[:space:]]*Secure Boot:' | head -n1 | cut -d: -f2- | xargs)"
      case "$secure_boot_raw" in
        [Ee]nabled*) secure_boot="Enabled" ;;
        [Dd]isabled*) secure_boot="Disabled" ;;
        *) [ -n "$secure_boot_raw" ] && secure_boot="$secure_boot_raw" ;;
      esac

      disk_encryption="Unknown"
      if lsblk -no TYPE >/dev/null 2>&1; then
        if lsblk -no TYPE | grep -q '^crypt$' || lsblk -no FSTYPE | grep -q '^crypto_LUKS$'; then
          disk_encryption="Enabled"
        else
          disk_encryption="Disabled"
        fi
      fi

      if [ "$json_output" = true ]; then
        cat <<JSON
      {"ghaf_version":"$ghaf_version","secure_boot":"$secure_boot","disk_encryption":"$disk_encryption"}
      JSON
      else
        cat <<INFO
      Ghaf Version: $ghaf_version
      Secure Boot: $secure_boot
      Disk Encryption: $disk_encryption
      INFO
      fi
    '';
  };
in
{
  _file = ./sysinfo.nix;

  options.ghaf.services.sysinfo.enable = mkOption {
    type = types.bool;
    default = true;
    description = "Enable ghaf sysinfo app";
  };

  config = mkIf cfg.enable {
    environment.systemPackages = [ ghafSysinfo ];
  };
}
