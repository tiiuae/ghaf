# Copyright 2022-2023 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  pkgs,
  lib,
  config,
  microvm,
  ...
}: let
  cfg = config.ghaf.programs.firefox;

  #
  # Scaled down firefox icon
  #
  firefox-icon = pkgs.runCommand "firefox-icon-24x24" {} ''
    mkdir -p $out/share/icons/hicolor/24x24/apps
    ${pkgs.buildPackages.imagemagick}/bin/convert \
      ${pkgs.firefox}/share/icons/hicolor/128x128/apps/firefox.png \
      -resize 24x24 \
      $out/share/icons/hicolor/24x24/apps/firefox.png
  '';
in {
  options.ghaf.programs.firefox = {
    enable = lib.mkEnableOption "Enable Firefox and launchers";
  };

  environment.systemPackages = lib.mkIf isHostOnly [pkgs.firefox];
  # Determine if we are running in the host-only or a vm
  # TODO generalize the launchers to support other transport mechanisms
  # and window managers (framework/launchers.nix)
  # TODO add launcher for the VM case
  ghaf.graphics.weston.launchers =
    (ho: {
      path =
        if ho
        then "${pkgs.firefox}/bin/firefox"
        else "";
      icon =
        if ho
        then "${firefox-icon}/share/icons/hicolor/24x24/apps/firefox.png"
        else "";
    })
    isHostOnly;

  # If running in the host add the app to the system packages
  environment.systemPackages = lib.mkIf isHostOnly [pkgs.firefox];

  #If running in a virtualized platform define the vm configuration
  # TODO can this be generalized into a "vm maker function
  # TODO Test this in a VM
  ghaf.virtualization.microvm.appvm.vms = lib.mkIf (! isHostOnly) {
    name = "firefox";
    packages = [pkgs.firefox];
    macAddress = "02:00:00:03:08:01";
    ramMb = 1536;
    cores = 2;
    extraModules = [
      {
        # TODO What does Firefox need in the VM
        # Likely same as chrome so an either/or?
      }
    ];
  };
}
