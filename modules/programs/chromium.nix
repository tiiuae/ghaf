# Copyright 2022-2023 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  config,
  lib,
  pkgs,
  microvm,
  ...
}: let
  cfg = config.ghaf.programs.chromium;
  isHostOnly = config.ghaf.profiles.hostOnly.enable;
in {
  options.ghaf.programs.chromium = {
    enable = lib.mkEnableOption "Enable Chromium and launchers";
  };

  config = lib.mkIf cfg.enable {
    # Determine if we are running in the host-only or a vm
    # TODO generalize the launchers to support other transport mechanisms
    # and window managers (framework/launchers.nix)
    ghaf.graphics.weston.launchers =
      (ho: {
        path =
          if ho
          then "${pkgs.chromium}/bin/chromium --enable-features=UseOzonePlatform --ozone-platform=wayland"
          else "${pkgs.openssh}/bin/ssh -i /run/waypipe-ssh/id_ed25519 -o StrictHostKeyChecking=no chromium-vm.ghaf ${pkgs.waypipe}/bin/waypipe --border \"#ff5733,5\" --vsock -s ${toString guivmConfig.waypipePort} server chromium --enable-features=UseOzonePlatform --ozone-platform=wayland";
        icon =
          if ho
          then "${pkgs.chromium}/share/icons/hicolor/24x24/apps/chromium.png"
          else "${../../assets/icons/png/browser.png}";
      })
      isHostOnly;

    # If running in the host add the app to the system packages
    environment.systemPackages = lib.mkIf isHostOnly [pkgs.chromium];

    # If running in a virtualized platform define the vm configuration
    # TODO can this be generalized into a "vm maker function
    ghaf.virtualization.microvm.appvm.vms = lib.mkIf (! isHostOnly) {
      name = "chromium";
      packages = [pkgs.chromium pkgs.pamixer];
      macAddress = "02:00:00:03:05:01";
      ramMb = 3072;
      cores = 4;
      extraModules = [
        {
          sound.enable = true;
          hardware.pulseaudio.enable = true;
          users.extraUsers.ghaf.extraGroups = ["audio"];

          microvm.qemu.extraArgs = [
            "-device"
            "qemu-xhci"
            "-device"
            "usb-host,vendorid=0x04f2,productid=0xb751"
            "-audiodev"
            "pa,id=pa1,server=unix:/run/pulse/native"
            "-device"
            "intel-hda"
            "-device"
            "hda-duplex,audiodev=pa1"
          ];
          microvm.devices = [];
        }
      ];
    };
  };
}
