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
    # Let the ghaf user set a one-shot BootNext without a password, and nothing
    # else. `ghaf-hw-test netboot` needs this to reboot a machine into PXE by
    # itself; without it the tool can only ask a human to do it.
    #
    # Scoped deliberately narrowly:
    #   * this module only, so it is debug-only and never reaches a release image
    #   * x86_64 only, matching where the netboot flow is used
    #   * the efibootmgr binary alone, not a blanket NOPASSWD for wheel
    security.sudo.extraRules = lib.mkIf (config.nixpkgs.hostPlatform.system == "x86_64-linux") [
      {
        users = [ "ghaf" ];
        commands = [
          {
            command = "${pkgs.efibootmgr}/bin/efibootmgr";
            options = [ "NOPASSWD" ];
          }
          # Setting a BootNext you cannot act on is useless, so this is scoped
          # to the reboot verb alone rather than to systemctl generally.
          {
            command = "${config.systemd.package}/bin/systemctl reboot";
            options = [ "NOPASSWD" ];
          }
        ];
      }
    ];

    environment.systemPackages =
      (rmDesktopEntries [
        # EFI tools for enrolling certs
        pkgs.efitools
      ])
      ++ lib.optionals (config.nixpkgs.hostPlatform.system == "x86_64-linux") (rmDesktopEntries [
        rm-linux-bootmgrs
        # To inspect LUKS partitions metadata
        pkgs.cryptsetup
        pkgs.lvm2
        # check hardware info
        pkgs.lshw
        # List microvm status
        pkgs.ghaf-vms
      ]);
  };
}
