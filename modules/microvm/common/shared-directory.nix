# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{ lib, config, ... }:
let
  cfg = config.ghaf.storagevm.shared-folders;
  inherit (lib) mkEnableOption;
  shared-mountPath = "/tmp/shared/shares";
  userDir =
    if cfg.isGuiVm then "/Shares" else "/home/${config.ghaf.users.appUser.name}/Unsafe\ share";
in
{
  _file = ./shared-directory.nix;
  options.ghaf.storagevm.shared-folders = {
    enable = mkEnableOption "Enable shared directory";
    isGuiVm = mkEnableOption "Indicate if the VM is the GUI VM";
  };

  config = lib.mkIf cfg.enable {
    fileSystems.${shared-mountPath}.neededForBoot = true;

    microvm.shares = [
      {
        tag = "shared-directory";
        proto = "virtiofs";
        securityModel = "passthrough";
        # We want double dir to keep root permission for `shared` directory and `shares` will be allowed to view and change by user.
        source =
          "/persist/storagevm/shared/shares"
          + (if !cfg.isGuiVm then "/Unsafe\ ${config.networking.hostName}\ share/" else "");
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
    environment.etc = {
      "skel/.gtk-bookmarks".text = ''
        file:///Shares Shares
      '';
    };
  };
}
