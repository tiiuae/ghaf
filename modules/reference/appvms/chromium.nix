# Copyright 2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
{
  pkgs,
  lib,
  config,
  ...
}:
let
  xdgPdfPort = 1200;
  name = "chromium";
in
{
  name = "${name}";
  packages =
    let
      # PDF XDG handler is executed when the user opens a PDF file in the browser
      # The xdgopenpdf script sends a command to the guivm with the file path over TCP connection
      xdgPdfItem = pkgs.makeDesktopItem {
        name = "ghaf-pdf";
        desktopName = "Ghaf PDF handler";
        exec = "${xdgOpenPdf}/bin/xdgopenpdf %u";
        mimeTypes = [ "application/pdf" ];
      };
      xdgOpenPdf = pkgs.writeShellScriptBin "xdgopenpdf" ''
        filepath=$(/run/current-system/sw/bin/realpath "$1")
        echo "Opening $filepath" | systemd-cat -p info
        echo $filepath | ${pkgs.netcat}/bin/nc -N gui-vm ${toString xdgPdfPort}
      '';
    in
    [
      pkgs.chromium
      pkgs.xdg-utils
      xdgPdfItem
      xdgOpenPdf
    ]
    ++ lib.optional config.ghaf.development.debug.tools.enable pkgs.alsa-utils;
  # TODO create a repository of mac addresses to avoid conflicts
  macAddress = "02:00:00:03:05:01";
  ramMb = 6144;
  cores = 4;
  extraModules = [
    {
      imports = [ ../programs/chromium.nix ];

      time.timeZone = config.time.timeZone;

      # Disable camera for now, because, due to the bug, the camera is not accessable in BusinessVM
      # microvm.qemu.extraArgs = optionals (
      #   config.ghaf.hardware.usb.internal.enable
      #   && (hasAttr "cam0" config.ghaf.hardware.usb.internal.qemuExtraArgs)
      # ) config.ghaf.hardware.usb.internal.qemuExtraArgs.cam0;
      microvm.devices = [ ];

      ghaf.givc.appvm = {
        enable = true;
        name = lib.mkForce "chromium-vm";
        applications = lib.mkForce ''
          {
            "chromium": "${config.ghaf.givc.appPrefix}/run-waypipe ${config.ghaf.givc.appPrefix}/chromium --enable-features=UseOzonePlatform --ozone-platform=wayland ${config.ghaf.givc.idsExtraArgs}"
          }'';
      };

      ghaf.reference.programs.chromium.enable = true;

      # Set default PDF XDG handler
      xdg.mime.defaultApplications."application/pdf" = "ghaf-pdf.desktop";
    }
  ];
  borderColor = "#630505";
  ghafAudio.enable = true;
  vtpm.enable = true;
}
