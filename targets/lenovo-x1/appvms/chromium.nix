# Copyright 2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
{pkgs, ...}: let
  xdgPdfPort = 1200;
in {
  name = "chromium";
  packages = let
    # PDF XDG handler is executed when the user opens a PDF file in the browser
    # The xdgopenpdf script sends a command to the guivm with the file path over TCP connection
    xdgPdfItem = pkgs.makeDesktopItem {
      name = "ghaf-pdf";
      desktopName = "Ghaf PDF handler";
      exec = "${xdgOpenPdf}/bin/xdgopenpdf %u";
      mimeTypes = ["application/pdf"];
    };
    xdgOpenPdf = pkgs.writeShellScriptBin "xdgopenpdf" ''
      filepath=$(realpath $1)
      echo "Opening $filepath" | systemd-cat -p info
      echo $filepath | ${pkgs.netcat}/bin/nc -N gui-vm.ghaf ${toString xdgPdfPort}
    '';
  in [
    pkgs.chromium
    pkgs.pamixer
    pkgs.xdg-utils
    xdgPdfItem
    xdgOpenPdf
  ];
  # TODO create a repository of mac addresses to avoid conflicts
  macAddress = "02:00:00:03:05:01";
  ramMb = 3072;
  cores = 4;
  extraModules = [
    {
      # Enable pulseaudio for user ghaf
      sound.enable = true;
      hardware.pulseaudio.enable = true;
      users.extraUsers.ghaf.extraGroups = ["audio"];

      time.timeZone = "Asia/Dubai";

      microvm.qemu.extraArgs = [
        # Connect sound device to hosts pulseaudio socket
        "-audiodev"
        "pa,id=pa1,server=unix:/run/pulse/native"
        # Add HDA sound device to guest
        "-device"
        "intel-hda"
        "-device"
        "hda-duplex,audiodev=pa1"
        # Lenovo X1 integrated usb webcam
        "-device"
        "qemu-xhci"
        "-device"
        "usb-host,hostbus=3,hostport=8"
      ];
      microvm.devices = [];

      # Disable chromium built-in PDF viewer to make it execute xdg-open
      programs.chromium.enable = true;
      programs.chromium.extraOpts."AlwaysOpenPdfExternally" = true;
      # Set default PDF XDG handler
      xdg.mime.defaultApplications."application/pdf" = "ghaf-pdf.desktop";
      # Import promtail agent for remote upload of journal logs
      imports = [
        (import ../../../modules/common/log/promtail-agent.nix {
          inherit pkgs;
          hostName = "chromium-vm";
        })
      ];
    }
  ];
  borderColor = "#630505";
}
