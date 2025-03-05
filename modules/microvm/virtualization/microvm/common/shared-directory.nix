# Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
name:
{ lib, config, ... }:
let
  cfg = config.ghaf.storagevm;
  isGuiVm = builtins.stringLength name == 0;
  shared-mountPath = "/tmp/shared/shares";
  userDir = if isGuiVm then "/Shares" else "/home/${config.ghaf.users.appUser.name}/Unsafe\ share";
in
{
  config = lib.mkIf cfg.enable {
    fileSystems.${shared-mountPath}.neededForBoot = true;

    microvm.shares = [
      {
        tag = "shared-directory";
        proto = "virtiofs";
        securityModel = "passthrough";
        # We want double dir to keep root permission for `shared` directory and `shares` will be allowed to view and change by user.
        source = "/persist/storagevm/shared/shares" + (if !isGuiVm then "/Unsafe\ ${name}\ share/" else "");
        mountPoint = shared-mountPath;
      }
    ];

    # https://github.com/nix-community/impermanence/blob/master/nixos.nix#L61-L70
    fileSystems.${userDir} = {
      depends = [ shared-mountPath ];
      device = shared-mountPath;
      noCheck = true;
      mountPoint = userDir;
      fsType = "none";
      options = [
        "bind"
        "X-fstrim.notrim"
        "x-gvfs-hide"
      ];
    };

    # Add bookmark to skel
    environment.etc = lib.mkIf config.ghaf.users.loginUser.enable {
      "skel/.gtk-bookmarks".text = ''
        file:///Shares Shares
      '';
    };
  };
}
