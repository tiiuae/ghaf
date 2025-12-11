# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
{
  config,
  lib,
  pkgs,
  ...
}:

let
  inherit (lib) mkIf mkEnableOption;

  cfg = config.ghaf.hardware.lenovo-x1-efi-uki;

  # Kernel command line from config (no system.build.toplevel here to avoid recursion)
  kernelCmdline = lib.concatStringsSep " " config.boot.kernelParams;

  ghafX1Uki =
    pkgs.runCommand "ghaf-x1-uki"
      {
        nativeBuildInputs = [ pkgs.systemdUkify ];
      }
      ''
            set -e
            echo "Building UKI for Lenovo X1 with config-based cmdline…"

            mkdir -p "$out/EFI/BOOT"

            # Provide an os-release file so ukify doesn't try /usr/lib/os-release
            cat > os-release <<'EOF'
        NAME="Ghaf"
        ID=ghaf
        PRETTY_NAME="Ghaf (Lenovo X1 UKI)"
        VERSION_ID="debug"
        EOF

            "${pkgs.systemdUkify}/bin/ukify" build \
              --linux  "${config.system.build.kernel}/${config.system.boot.loader.kernelFile}" \
              --initrd "${config.system.build.initialRamdisk}/${config.system.boot.loader.initrdFile}" \
              --cmdline ${lib.escapeShellArg kernelCmdline} \
              --os-release=@os-release \
              --output "$out/EFI/BOOT/BOOTX64.EFI"

      '';
in
{
  options.ghaf.hardware.lenovo-x1-efi-uki.enable = mkEnableOption "custom UKI for Lenovo X1";

  config = mkIf cfg.enable {
    system.build.ghafX1Uki = ghafX1Uki;

    boot.loader.systemd-boot.extraFiles = {
      "EFI/BOOT/BOOTX64.EFI" = "${ghafX1Uki}/EFI/BOOT/BOOTX64.EFI";
    };
  };
}
