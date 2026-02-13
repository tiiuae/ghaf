# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.ghaf.development.debug.tools.host;

  rm-linux-bootmgrs = pkgs.callPackage ./scripts/rm_linux_bootmgr_entries.nix { };

  inherit (lib) rmDesktopEntries;
in
{
  _file = ./dt-host.nix;

  options.ghaf.development.debug.tools.host.enable = lib.mkEnableOption "Host Debugging Tools";

  config = lib.mkIf cfg.enable {
    environment.systemPackages =
      (rmDesktopEntries [
        # EFI tools for enrolling certs
        pkgs.efitools
      ])
      ++ lib.optionals (config.nixpkgs.hostPlatform.system == "x86_64-linux") (rmDesktopEntries [
        rm-linux-bootmgrs
        # To inspect LUKS partitions metadata
        pkgs.cryptsetup
        # check hardware info
        pkgs.lshw
        # List microvm status
        pkgs.ghaf-vms
      ]);
  };
}
