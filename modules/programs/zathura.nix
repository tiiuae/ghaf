# Copyright 2022-2023 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  config,
  lib,
  pkgs,
  microvm,
  ...
}: let
  cfg = config.ghaf.programs.zathura;
  isHostOnly = config.ghaf.profiles.hostOnly.enable;
in {
  options.ghaf.programs.zathura = {
    enable = lib.mkEnableOption "Enable Zathura and launchers";
  };

  config = lib.mkIf cfg.enable {
    # Determine if we are running in the host-only or a vm
    # TODO generalize the launchers to support other transport mechanisms
    # and window managers (framework/launchers.nix)
    ghaf.graphics.weston.launchers =
      (ho: {
        path =
          if ho
          then "${pkgs.zathura}/bin/zathura"
          else "${pkgs.openssh}/bin/ssh -i /run/waypipe-ssh/id_ed25519 -o StrictHostKeyChecking=no zathura-vm.ghaf ${pkgs.waypipe}/bin/waypipe --border \"#337aff,5\" --vsock -s ${toString guivmConfig.waypipePort} server zathura";
        icon =
          if ho
          then "${pkgs.zathura}/share/icons/hicolor/32x32/apps/org.pwmt.zathura.png"
          else "${../../assets/icons/png/pdf.png}";
      })
      isHostOnly;

    # If running in the host add the app to the system packages
    environment.systemPackages = lib.mkIf isHostOnly [pkgs.zathura];

    # If running in a virtualized platform define the vm configuration
    # TODO can this be generalized into a "vm maker function
    ghaf.virtualization.microvm.appvm.vms = lib.mkIf (! isHostOnly) {
      name = "zathura";
      packages = [pkgs.zathura];
      macAddress = "02:00:00:03:07:01";
      ramMb = 512;
      cores = 1;
    };
  };
}
