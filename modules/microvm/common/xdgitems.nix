# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
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
  inherit (config.ghaf.networking) hosts;
  inherit (lib)
    optionalString
    mkEnableOption
    mkOption
    types
    mkIf
    optionalAttrs
    optionals
    ;
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
    "image/x-panasonic-raw"
    "image/x-portable-pixmap"
    "image/heic"
    "image/x-qoi"
  ];

  # Taken from supported MIME types by COSMIC Player
  # Ref.: https://github.com/pop-os/cosmic-player/blob/master/res/com.system76.CosmicPlayer.desktop
  supportedVideoMimeTypes = [
    "application/mxf"
    "application/ram"
    "application/sdp"
    "application/vnd.apple.mpegurl"
    "application/vnd.ms-asf"
    "application/vnd.ms-wpl"
    "application/vnd.rn-realmedia"
    "application/vnd.rn-realmedia-vbr"
    "application/x-extension-m4a"
    "application/x-extension-mp4"
    "application/x-flash-video"
    "application/x-matroska"
    "application/x-netshow-channel"
    "application/x-quicktimeplayer"
    "application/x-shorten"
    "image/vnd.rn-realpix"
    "image/x-pict"
    "misc/ultravox"
    "text/x-google-video-pointer"
    "video/3gp"
    "video/3gpp"
    "video/3gpp2"
    "video/dv"
    "video/divx"
    "video/fli"
    "video/flv"
    "video/mp2t"
    "video/mp4"
    "video/mp4v-es"
    "video/mpeg"
    "video/mpeg-system"
    "video/msvideo"
    "video/ogg"
    "video/quicktime"
    "video/vivo"
    "video/vnd.divx"
    "video/vnd.mpegurl"
    "video/vnd.rn-realvideo"
    "video/vnd.vivo"
    "video/webm"
    "video/x-anim"
    "video/x-avi"
    "video/x-flc"
    "video/x-fli"
    "video/x-flic"
    "video/x-flv"
    "video/x-m4v"
    "video/x-matroska"
    "video/x-mjpeg"
    "video/x-mpeg"
    "video/x-mpeg2"
    "video/x-ms-asf"
    "video/x-ms-asf-plugin"
    "video/x-ms-asx"
    "video/x-msvideo"
    "video/x-ms-wm"
    "video/x-ms-wmv"
    "video/x-ms-wmx"
    "video/x-ms-wvx"
    "video/x-nsv"
    "video/x-ogm+ogg"
    "video/x-theora"
    "video/x-theora+ogg"
    "video/x-totem-stream"
    "audio/x-pn-realaudio"
    "application/smil"
    "application/smil+xml"
    "application/x-quicktime-media-link"
    "application/x-smil"
    "text/google-video-pointer"
    "x-content/video-dvd"
    "x-scheme-handler/pnm"
    "x-scheme-handler/mms"
    "x-scheme-handler/net"
    "x-scheme-handler/rtp"
    "x-scheme-handler/rtmp"
    "x-scheme-handler/rtsp"
    "x-scheme-handler/mmsh"
    "x-scheme-handler/uvox"
    "x-scheme-handler/icy"
    "x-scheme-handler/icyx"
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

  # XDG item for documents
  xdgPdfItem = pkgs.makeDesktopItem {
    name = "ghaf-pdf-xdg";
    desktopName = "Ghaf Isolated Document Viewer";
    icon = "com.system76.CosmicReader";
    exec = "${lib.getExe xdgOpen} pdf %u";
    mimeTypes = [ "application/pdf" ];
    onlyShowIn = [ "X-Ghaf-Internal" ];
  };

  # XDG item for images
  xdgImageItem = pkgs.makeDesktopItem {
    name = "ghaf-image-xdg";
    desktopName = "Ghaf Isolated Image Viewer";
    icon = "multimedia-photo-viewer";
    exec = "${lib.getExe xdgOpen} image %u";
    mimeTypes = supportedImageMimeTypes;
    onlyShowIn = [ "X-Ghaf-Internal" ];
  };

  # XDG item for video files
  xdgVideoItem = pkgs.makeDesktopItem {
    name = "ghaf-video-xdg";
    desktopName = "Ghaf Isolated Media Player";
    icon = "com.system76.CosmicPlayer";
    exec = "${lib.getExe xdgOpen} video %u";
    mimeTypes = supportedVideoMimeTypes;
    onlyShowIn = [ "X-Ghaf-Internal" ];
  };

  # XDG item for URL
  xdgUrlItem = pkgs.makeDesktopItem {
    name = "ghaf-url-xdg";
    desktopName = "Ghaf URL Opener";
    exec = "${lib.getExe xdgOpen} url %u";
    mimeTypes = [
      "text/html"
      "x-scheme-handler/http"
      "x-scheme-handler/https"
    ];
    onlyShowIn = [ "X-Ghaf-Internal" ];
  };

  # XDG item for element-desktop
  xdgElementDesktopItem = pkgs.makeDesktopItem {
    name = "ghaf-element-xdg";
    desktopName = "Ghaf Element Desktop";
    exec = "${lib.getExe xdgOpen} element %u";
    mimeTypes = [
      "x-scheme-handler/io.element.desktop"
      "x-scheme-handler/element"
    ];
    onlyShowIn = [ "X-Ghaf-Internal" ];
  };

  # The XDG open script is used by XDG items to copy the file
  # to the shared location (e.g., /run/xdg/pdf/chrome-vm) and
  # start the application in the VM responsible for that file type
  # (currently only media-vm) using GIVC
  xdgOpen = pkgs.writeShellApplication {
    name = "xdg-open-ghaf";

    runtimeInputs = [
      pkgs.coreutils
    ];

    text =
      let
        urlVmName =
          if config.ghaf.xdghandlers.url.enable then
            "${config.networking.hostName}"
          else if lib.hasAttr "chrome-vm" hosts then
            "chrome-vm"
          else if lib.hasAttr "chromium-vm" hosts then
            "chromium-vm"
          else
            "";

        openExternalUrl = optionalString (urlVmName != "") ''
          open_url() {
            echo "Opening URL in ${urlVmName}: $resource"

            ${pkgs.givc-cli}/bin/givc-cli ${config.ghaf.givc.cliArgs} \
              start app --vm "${urlVmName}" "xdg-url" -- "$resource"
          }

          if [[ "$resourceType" == "url" ]]; then
            open_url
          fi
        '';
      in
      ''
          resourceType=$1
          resource=$2

          open_element_desktop() {
            echo "Opening Element desktop in comms-vm: $resource"
            ${pkgs.givc-cli}/bin/givc-cli ${config.ghaf.givc.cliArgs} \
              start app --vm comms-vm "xdg-element-desktop" -- "$resource"
          }

          ${openExternalUrl}

          open_file() {
            local type=$1
            local file=$2

            local fileName
            fileName=$(basename "$file")
            local filePath
            filePath=$(realpath "$file" || true)

            if [[ -z "$filePath" || ! -f "$filePath" ]]; then
              echo "Error: file does not exist: $file"
              exit 1
            fi

            case "$type" in
              pdf|image|video)
                echo "Opening $filePath as $type"
                mkdir -p "/run/xdg/$type"
                cp -f "$filePath" "/run/xdg/$type/$fileName"

                local dst="/run/xdg/$type/${config.ghaf.storagevm.name}/$fileName"
                ${pkgs.givc-cli}/bin/givc-cli ${config.ghaf.givc.cliArgs} \
                  start app --vm media-vm "xdg-$type" -- "$dst"
                ;;
              *)
                echo "Error: unsupported file type '$type'"
                exit 1
                ;;
            esac
          }

        if [[ "$resourceType" == "element" ]]; then
          open_element_desktop
        else
          open_file "$resourceType" "$resource"
        fi
      '';
  };
in
{
  options.ghaf.xdgitems = {
    enable = mkEnableOption "XDG Desktop Items";

    handlerPath = mkOption {
      description = "Path of the XDG open file script used by the AppArmor module to whitelist it";
      type = types.str;
      default = "";
      visible = false;
    };

    xdgHostRoot = mkOption {
      description = "Path of the XDG root folder used for file sharing between VMs";
      type = types.str;
      default = "/persist/storagevm/xdg";
    };

    xdgHostPaths = mkOption {
      description = "List of XDG directories for AppVMs where XDG items are enabled";
      type = types.listOf types.str;
      readOnly = true;
      visible = false;
    };

    elementDesktop.enable = mkEnableOption "XDG Element Desktop Item";
  };

  config = mkIf (cfg.enable && config.ghaf.givc.enable) {

    ghaf.xdgitems.handlerPath = xdgOpen.outPath;

    systemd.tmpfiles.rules = mkIf config.ghaf.users.appUser.enable [
      # Create parent directory if missing
      "d /home/${config.ghaf.users.appUser.name}/.config 0751 ${config.ghaf.users.appUser.name} users -"
      # Create or update symlink
      "L+ /home/${config.ghaf.users.appUser.name}/.config/mimeapps.list - - - - /etc/xdg/mimeapps.list"
    ];

    ghaf.xdgitems.xdgHostPaths = [
      "${xdgHostRoot}/pdf/${vmName}"
      "${xdgHostRoot}/image/${vmName}"
      "${xdgHostRoot}/video/${vmName}"
    ];

    environment.systemPackages = [
      pkgs.xdg-utils
      xdgPdfItem
      xdgImageItem
      xdgVideoItem
      xdgOpen
      xdgUrlItem
    ]
    ++ optionals cfg.elementDesktop.enable [ xdgElementDesktopItem ];

    # Set up XDG items for each supported MIME type
    xdg.mime.defaultApplications =
      setDefaultAppForTypes supportedImageMimeTypes "ghaf-image-xdg.desktop"
      // setDefaultAppForTypes supportedVideoMimeTypes "ghaf-video-xdg.desktop"
      // {
        "application/pdf" = "ghaf-pdf-xdg.desktop";
        "text/html" = "ghaf-url-xdg.desktop";
        "x-scheme-handler/http" = "ghaf-url-xdg.desktop";
        "x-scheme-handler/https" = "ghaf-url-xdg.desktop";
      }
      // optionalAttrs cfg.elementDesktop.enable {
        "x-scheme-handler/io.element.desktop" = "ghaf-element-xdg.desktop";
        # Optional: Element also sometimes uses the plain 'element' scheme
        "x-scheme-handler/element" = "ghaf-element-xdg.desktop";
      };

    # Set up MicroVM shares for each MIME type and mount them to /run/xdg
    # These shares are also passed to the VMs that handle XDG requests
    # Currently, only media-vm is used for PDF and JPG types
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
      {
        tag = "xdgshare-video-${vmName}";
        proto = "virtiofs";
        securityModel = "passthrough";
        source = "${xdgHostRoot}/video/${vmName}";
        mountPoint = "/run/xdg/video";
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
      "/run/xdg/video".options = [
        "rw"
        "nodev"
        "nosuid"
        "noexec"
      ];
    };
  };
}
