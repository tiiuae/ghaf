# Copyright 2022-2023 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  config,
  lib,
  pkgs,
  microvm,
  ...
}: let
  cfg = config.ghaf.programs.gala;
  isHostOnly = config.ghaf.profiles.hostOnly.enable;
in {
  options.ghaf.programs.gala = {
    enable = lib.mkEnableOption "Enable Gala and launchers";
  };

  config = lib.mkIf cfg.enable {
    # Determine if we are running in the host-only or a vm
    # TODO generalize the launchers to support other transport mechanisms
    # and window managers (framework/launchers.nix)
    ghaf.graphics.weston.launchers =
      (ho: {
        path =
          if ho
          then "${pkgs.gala-app}/bin/gala --enable-features=UseOzonePlatform --ozone-platform=wayland"
          else "${pkgs.openssh}/bin/ssh -i /run/waypipe-ssh/id_ed25519 -o StrictHostKeyChecking=no gala-vm.ghaf ${pkgs.waypipe}/bin/waypipe --border \"#33ff57,5\" --vsock -s ${toString guivmConfig.waypipePort} server gala --enable-features=UseOzonePlatform --ozone-platform=wayland";
        icon =
          if ho
          then "${pkgs.gala-app}/gala/resources/icon-24x24.png"
          else "${../../assets/icons/png/app.png}";
      })
      isHostOnly;

    # If running in the host add the app to the system packages
    environment.systemPackages = lib.mkIf isHostOnly [pkgs.gala-app];

    # If running in a virtualized platform define the vm configuration
    # TODO can this be generalized into a "vm maker function
    ghaf.virtualization.microvm.appvm.vms = lib.mkIf (! isHostOnly) {
      name = "gala";
      packages = [pkgs.gala-app];
      macAddress = "02:00:00:03:06:01";
      ramMb = 1536;
      cores = 2;
    };
  };
}
