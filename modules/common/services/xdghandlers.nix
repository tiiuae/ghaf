# Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.ghaf.services.xdghandlers;
  inherit (lib)
    mkIf
    mkEnableOption
    ;
  # XDG item for PDF
  xdgPdfItem = pkgs.makeDesktopItem {
    name = "ghaf-pdf-xdg";
    desktopName = "Ghaf PDF Viewer";
    exec = "${xdgOpenFile}/bin/xdgopenfile pdf %f";
    mimeTypes = [ "application/pdf" ];
    noDisplay = true;
  };
  # XDG item for JPG and PNG
  xdgImageItem = pkgs.makeDesktopItem {
    name = "ghaf-image-xdg";
    desktopName = "Ghaf Image Viewer";
    exec = "${xdgOpenFile}/bin/xdgopenfile image %f";
    mimeTypes = [
      "image/jpeg"
      "image/png"
    ];
    noDisplay = true;
  };
  # The xdgopenfile script sends a command to the GUIVM with the file path and type over TCP connection
  xdgOpenFile = pkgs.writeShellApplication {

    name = "xdgopenfile";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.netcat
      pkgs.systemd
    ];
    text = ''
      type=$1
      filename=$2
      filepath=$(realpath "$filename")
      if [[ -z "$filepath" ]]; then
        echo "File path is empty in the XDG open script" | systemd-cat -p info
        exit 1
      fi
      if [[ "$type" != "pdf" && "$type" != "image" ]]; then
        echo "Unknown file type in the XDF open script" | systemd-cat -p info
        exit 1
      fi
      echo "Opening $filepath with type $type" | systemd-cat -p info
      echo -e "$type\n$filepath" | nc -N gui-vm ${toString config.ghaf.services.xdgopener.xdgPort}
    '';
  };
in
{
  options.ghaf.services.xdghandlers = {
    enable = mkEnableOption "Enable Ghaf XDG handlers";
    handlerPath = lib.mkOption {
      description = "Path of xdgHandler script.";
      type = lib.types.str;
    };
  };
  config = mkIf cfg.enable {
    ghaf.services.xdghandlers.handlerPath = xdgOpenFile.outPath;
    environment.systemPackages = [
      pkgs.xdg-utils
      xdgPdfItem
      xdgImageItem
      xdgOpenFile
    ];

    xdg.mime.defaultApplications."application/pdf" = "ghaf-pdf-xdg.desktop";
    xdg.mime.defaultApplications."image/jpeg" = "ghaf-image-xdg.desktop";
    xdg.mime.defaultApplications."image/png" = "ghaf-image-xdg.desktop";
  };
}
