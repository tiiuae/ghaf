# Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.ghaf.profiles.debug;
in
{
  options.ghaf.profiles.debug = {
    enable = (lib.mkEnableOption "debug profile") // {
      default = !config.ghaf.profiles.release.enable;
    };
  };

  config = lib.mkIf cfg.enable {
    # Enable default accounts and passwords
    ghaf = {
      # Enable development on target
      # TODO: we should import the module that defines the development namespace
      # see the graphics.nix example including the desktop module to get ghaf.graphics
      development = {
        nix-setup.enable = true;
        # Enable some basic monitoring and debug tools
        debug.tools.enable = true;
        # Let us in.
        ssh.daemon.enable = true;
        usb-serial.enable = true;
      };

    };
    environment.systemPackages = [
      pkgs.lynis
      pkgs.nmap
      pkgs.toybox
    ];
  };
}
#sudo scp /var/log/lynis* enes@192.168.1.8:/home/enes/ghaf-nw-sec/sysvms/admin-vm

#lsmod | awk '{ print $1 }' | grep "^ip*_tables"
