# Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
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
  sourceDir = "/storagevm/shared/shares/xdg/";

  cliArgs = lib.replaceStrings [ "\n" ] [ " " ] ''
    --name ${config.ghaf.givc.adminConfig.name}
    --addr ${config.ghaf.givc.adminConfig.addr}
    --port ${config.ghaf.givc.adminConfig.port}
    ${lib.optionalString config.ghaf.givc.enableTls "--cacert /run/givc/ca-cert.pem"}
    ${lib.optionalString config.ghaf.givc.enableTls "--cert /run/givc/ghaf-host-cert.pem"}
    ${lib.optionalString config.ghaf.givc.enableTls "--key /run/givc/ghaf-host-key.pem"}
    ${lib.optionalString (!config.ghaf.givc.enableTls) "--notls"}
  '';

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

  # TODO: fix the url hack once GIVC supports file path arguments
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
      encoded=$(echo -n "$dst" | base64)
      ${pkgs.givc-cli}/bin/givc-cli ${cliArgs} start --vm zathura-vm "xdg-$type" -- "http://example.com?p=$encoded"
    '';
  };
in
{
  options.ghaf.xdgitems = {
    enable = lib.mkEnableOption "XDG Desktop Items";
  };

  config = lib.mkIf (cfg.enable && config.ghaf.givc.enable) {
    environment.systemPackages = [
      pkgs.xdg-utils
      xdgPdfItem
      xdgImageItem
      xdgOpenFile
    ];

    xdg.mime.defaultApplications."application/pdf" = "ghaf-pdf-xdg.desktop";
    xdg.mime.defaultApplications."image/jpeg" = "ghaf-image-xdg.desktop";
    xdg.mime.defaultApplications."image/png" = "ghaf-image-xdg.desktop";

    microvm.shares = [
      {
        tag = "xdgshare-pdf-${vmName}";
        proto = "virtiofs";
        securityModel = "passthrough";
        source = "${sourceDir}/pdf/${vmName}";
        mountPoint = "/run/xdg/pdf";
      }
      {
        tag = "xdgshare-image-${vmName}";
        proto = "virtiofs";
        securityModel = "passthrough";
        source = "${sourceDir}/image/${vmName}";
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

    systemd.tmpfiles.rules = [
      "d /run/xdg/pdf 0700 ${toString config.ghaf.users.loginUser.uid}"
      "d /run/xdg/image 0700 ${toString config.ghaf.users.loginUser.uid}"
    ];
  };
}
