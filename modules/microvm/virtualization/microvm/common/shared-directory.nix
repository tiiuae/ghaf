# Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
name:
{ lib, config, ... }:
let
  cfg = config.ghaf.storagevm;
  shared-mountPath = "/tmp/shared/shares";
  inherit (config.ghaf.users.accounts) user;
  isGuiVm = builtins.stringLength name == 0;
  userDir = "/home/${user}" + (if isGuiVm then "/Shares" else "/Unsafe\ share");
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
        source = "/storagevm/shared/shares" + (if !isGuiVm then "/Unsafe\ ${name}\ share/" else "");
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
  };
}
