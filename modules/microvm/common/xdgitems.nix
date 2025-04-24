# Copyright 2022-2025 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  lib,
  config,
  pkgs,
  ...
}:
let
  cfg = config.ghaf.xdgitems;
  vmName = config.ghaf.storagevm.name;
  inherit (cfg) xdgHostRoot;

  # Taken from supported MIME types by Oculante
  # Ref.: https://github.com/woelper/oculante/blob/master/res/oculante.desktop
  supportedImageMimeTypes = [
    "image/bmp"
    "image/gif"
    "image/vnd.microsoft.icon"
    "image/jpeg"
    "image/jp2"
    "image/png"
    "image/pnm"
    "image/x-tga"
    "image/jxl"
    "image/avif"
    "image/tiff"
    "image/webp"
    "image/octet-stream"
    "image/svg+xml"
    "image/exr"
    "image/x-exr"
    "image/x-dcraw"
    "image/x-nikon-nef"
    "image/x-canon-cr2"
    "image/x-adobe-dng"
    "image/x-epson-erf"
    "image/x-fuji-raf"
    "image/x-sony-arw"
    "image/x-sony-srf"
    "image/x-sony-sr2"
    "image/x-panasonic-raw/x-portable-pixmap"
    "image/heic"
    "image/x-qoi"
  ];

  # Maps a list of MIME types to a default application as an attribute set.
  # Example:
  #   setDefaultAppForTypes ["text/plain", "image/png"] "my-app.desktop"
  #   would produce:
  #   {
  #     "text/plain" = "my-app.desktop";
  #     "image/png" = "my-app.desktop";
  #   }
  setDefaultAppForTypes =
    mimeTypes: defaultApplication:
    lib.listToAttrs (
      map (mimeType: {
        name = mimeType;
        value = defaultApplication;
      }) mimeTypes
    );

  # XDG item for PDF
  xdgPdfItem = pkgs.makeDesktopItem {
    name = "ghaf-pdf-xdg";
    desktopName = "Ghaf PDF Viewer";
    icon = "document-viewer";
    exec = "${xdgOpenFile}/bin/xdgopenfile pdf %f";
    mimeTypes = [ "application/pdf" ];
    noDisplay = true;
  };

  # XDG item for JPG and PNG
  xdgImageItem = pkgs.makeDesktopItem {
    name = "ghaf-image-xdg";
    desktopName = "Ghaf Image Viewer";
    icon = "multimedia-photo-viewer";
    exec = "${xdgOpenFile}/bin/xdgopenfile image %f";
    mimeTypes = supportedImageMimeTypes;
    noDisplay = true;
  };

  # The XDG open script is used by XDG items to copy the file
  # to the shared location (e.g., /run/xdg/pdf/chrome-vm) and
  # start the application in the VM responsible for that file type
  # (currently only zathura-vm) using GIVC
  xdgOpenFile = pkgs.writeShellApplication {
    name = "xdgopenfile";
    runtimeInputs = [
      pkgs.coreutils
    ];
    text = ''
      type=$1
      file=$2
      filename=$(basename "$file")
      filepath=$(realpath "$file")
      if [[ -z "$filepath" ]]; then
        echo "File path is empty in the XDG open script"
        exit 1
      fi
      if [[ "$type" != "pdf" && "$type" != "image" ]]; then
        echo "Unknown file type in the XDF open script"
        exit 1
      fi
      echo "Opening $filepath with type $type"
      cp -f "$filepath" "/run/xdg/$type/$filename"
      dst="/run/xdg/$type/${config.ghaf.storagevm.name}/$filename"
      ${pkgs.givc-cli}/bin/givc-cli ${config.ghaf.givc.cliArgs} start app --vm zathura-vm "xdg-$type" -- "$dst"
    '';
  };
in
{
  options.ghaf.xdgitems = {
    enable = lib.mkEnableOption "XDG Desktop Items";

    handlerPath = lib.mkOption {
      description = "Path of the XDG open file script used by the AppArmor module to whitelist it";
      type = lib.types.str;
      readOnly = true;
      visible = false;
    };

    xdgHostRoot = lib.mkOption {
      description = "Path of the XDG root folder used for file sharing between VMs";
      type = lib.types.str;
      default = "/persist/storagevm/xdg";
    };

    xdgHostPaths = lib.mkOption {
      description = "List of XDG directories for AppVMs where XDG items are enabled";
      type = lib.types.listOf lib.types.str;
      readOnly = true;
      visible = false;
    };
  };

  config = lib.mkIf (cfg.enable && config.ghaf.givc.enable) {

    ghaf.xdgitems.handlerPath = xdgOpenFile.outPath;

    ghaf.xdgitems.xdgHostPaths = [
      "${xdgHostRoot}/pdf/${vmName}"
      "${xdgHostRoot}/image/${vmName}"
    ];

    environment.systemPackages = [
      pkgs.xdg-utils
      xdgPdfItem
      xdgImageItem
      xdgOpenFile
    ];

    # Set up XDG items for each supported MIME type
    xdg.mime.defaultApplications =
      setDefaultAppForTypes supportedImageMimeTypes "ghaf-image-xdg.desktop"
      // {
        "application/pdf" = "ghaf-pdf-xdg.desktop";
      };

    # Set up MicroVM shares for each MIME type and mount them to /run/xdg
    # These shares are also passed to the VMs that handle XDG requests
    # Currently, only zathura-vm is used for PDF and JPG types
    microvm.shares = [
      {
        tag = "xdgshare-pdf-${vmName}";
        proto = "virtiofs";
        securityModel = "passthrough";
        source = "${xdgHostRoot}/pdf/${vmName}";
        mountPoint = "/run/xdg/pdf";
      }
      {
        tag = "xdgshare-image-${vmName}";
        proto = "virtiofs";
        securityModel = "passthrough";
        source = "${xdgHostRoot}/image/${vmName}";
        mountPoint = "/run/xdg/image";
      }
    ];

    fileSystems = {
      "/run/xdg/pdf".options = [
        "rw"
        "nodev"
        "nosuid"
        "noexec"
      ];
      "/run/xdg/image".options = [
        "rw"
        "nodev"
        "nosuid"
        "noexec"
      ];
    };
  };
}
