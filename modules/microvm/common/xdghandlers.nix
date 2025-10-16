# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  lib,
  config,
  pkgs,
  ...
}:
let
  cfg = config.ghaf.xdghandlers;
  inherit (config.ghaf.xdgitems) xdgHostRoot;

  # A script for opening PDF files launched by GIVC from AppVMs
  xdgOpenPdf = pkgs.writeShellApplication {
    name = "xdgopenpdf";
    runtimeInputs = [ pkgs.coreutils ];
    text = ''
      file="$1"
      echo "XDG open PDF: $file"
      ${config.ghaf.givc.appPrefix}/run-waypipe ${config.ghaf.givc.appPrefix}/zathura "$file"
      rm "$file"
    '';
  };

  # A script for opening image files launched by GIVC from AppVMs
  xdgOpenImage = pkgs.writeShellApplication {
    name = "xdgopenimage";
    runtimeInputs = [ pkgs.coreutils ];
    text = ''
      file="$1"
      echo "XDG open image: $file"
      ${config.ghaf.givc.appPrefix}/run-waypipe ${config.ghaf.givc.appPrefix}/oculante "$file"
      rm "$file"
    '';
  };

  # A script for opening url launched by GIVC from AppVMs
  xdgOpenUrl = pkgs.writeShellApplication {
    name = "xdgopenurl";
    runtimeInputs = [
      pkgs.coreutils
    ];
    text = ''
        url="$1"
        if [[ -z "$url" ]]; then
          echo "No URL provided - xdg handlers"
          exit 1
        fi
        echo "XDG open url: $url"
      ${
        if config.networking.hostName == "chrome-vm" then
          ''${config.ghaf.givc.appPrefix}/run-waypipe ${config.ghaf.givc.appPrefix}/chrome-wrapper "$url"''
        else if config.networking.hostName == "chromium-vm" then
          ''${config.ghaf.givc.appPrefix}/run-waypipe ${config.ghaf.givc.appPrefix}/chromium --enable-features=UseOzonePlatform --ozone-platform=wayland "$url"''
        else
          ''echo "Host is not either chrome-vm nor chromium-vm, refusing to open URL"; exit 1''
      }
    '';
  };

  # A script for opening url launched by GIVC from AppVMs
  xdgOpenElement = pkgs.writeShellApplication {
    name = "xdgopenelement";
    runtimeInputs = [
      pkgs.coreutils
    ];
    text = ''
      url="$1"
      if [[ -z "$url" ]]; then
        echo "No element URL provided - xdg handlers"
        exit 1
      fi
      echo "XDG open element: $url"
      ${config.ghaf.givc.appPrefix}/run-waypipe ${config.ghaf.givc.appPrefix}/element-desktop --enable-logging --disable-gpu --enable-features=UseOzonePlatform --ozone-platform=wayland "$url"
    '';
  };

in
{
  options.ghaf.xdghandlers = {
    pdf = lib.mkEnableOption "XDG PDF Handler";
    image = lib.mkEnableOption "XDG Image Handler";
    url = lib.mkEnableOption "XDG Url Handler";
    elementDesktop = lib.mkEnableOption "XDG Element desktop Handler";
  };

  config = lib.mkIf config.ghaf.givc.enable {
    environment.systemPackages =
      (lib.optional cfg.pdf pkgs.zathura)
      ++ (lib.optional cfg.image pkgs.oculante)
      ++ (lib.optional cfg.url pkgs.google-chrome);

    ghaf.givc.appvm.applications =
      (lib.optional cfg.pdf {
        name = "xdg-pdf";
        command = "${xdgOpenPdf}/bin/xdgopenpdf";
        args = [ "file" ];
        directories = [ "/run/xdg/pdf" ];
      })
      ++ (lib.optional cfg.image {
        name = "xdg-image";
        command = "${xdgOpenImage}/bin/xdgopenimage";
        args = [ "file" ];
        directories = [ "/run/xdg/image" ];
      })
      ++ (lib.optional cfg.url {
        name = "xdg-url";
        command = "${xdgOpenUrl}/bin/xdgopenurl";
        args = [ "url" ];
      })
      ++ (lib.optional cfg.elementDesktop {
        name = "xdg-element-desktop";
        command = "${xdgOpenElement}/bin/xdgopenelement";
        args = [ "url" ];
      });

    # Set up MicroVM shares for each MIME type and mount them to /run/xdg
    # These shares are also passed to the AppVMs where XDG items are enabled
    microvm.shares =
      (lib.optional cfg.pdf {
        tag = "xdgshare-pdf";
        proto = "virtiofs";
        securityModel = "passthrough";
        source = "${xdgHostRoot}/pdf";
        mountPoint = "/run/xdg/pdf";
      })
      ++ (lib.optional cfg.image {
        tag = "xdgshare-image";
        proto = "virtiofs";
        securityModel = "passthrough";
        source = "${xdgHostRoot}/image";
        mountPoint = "/run/xdg/image";
      });

    fileSystems =
      (lib.optionalAttrs cfg.pdf {
        "/run/xdg/pdf".options = [
          "rw"
          "nodev"
          "nosuid"
          "noexec"
        ];
      })
      // (lib.optionalAttrs cfg.image {
        "/run/xdg/image".options = [
          "rw"
          "nodev"
          "nosuid"
          "noexec"
        ];
      });
  };
}
