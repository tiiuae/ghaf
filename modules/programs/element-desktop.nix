# Copyright 2022-2023 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  config,
  lib,
  pkgs,
  microvm,
  ...
}: let
  cfg = config.ghaf.programs.element-desktop;
  isHostOnly = config.ghaf.profiles.hostOnly.enable;
in {
  options.ghaf.programs.element-desktop = {
    enable = lib.mkEnableOption "Enable Element and launchers";
  };

  config = lib.mkIf cfg.enable {
    # Determine if we are running in the host-only or a vm
    # TODO generalize the launchers to support other transport mechanisms
    # and window managers (framework/launchers.nix)
    ghaf.graphics.weston.launchers =
      (ho: {
        path =
          if ho
          then "${pkgs.element-desktop-wayland}/bin/element-desktop --enable-features=UseOzonePlatform --ozone-platform=wayland"
          else "";
        icon =
          if ho
          then "${pkgs.element-desktop-wayland}/share/icons/hicolor/24x24/apps/element.png"
          else "";
      })
      isHostOnly;

    # If running in the host add the app to the system packages
    environment.systemPackages = lib.mkIf isHostOnly [pkgs.element-desktop-wayland];

    # If running in a virtualized platform define the vm configuration
    # TODO can this be generalized into a "vm maker function
    # TODO Test element-desktop in a VM
    ghaf.virtualization.microvm.appvm.vms = lib.mkIf (! isHostOnly) {
      name = "element-desktop";
      packages = [pkgs.element-desktop-wayland];
      macAddress = "02:00:00:03:09:01";
      ramMb = 1536;
      cores = 2;
    };
  };
}
