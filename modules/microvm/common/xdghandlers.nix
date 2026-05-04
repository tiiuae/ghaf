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

  # Helper to create an XDG file-opener script launched by GIVC from AppVMs
  mkXdgFileOpener =
    {
      name,
      package,
      execCmd ? lib.getExe package,
      serviceType ? "simple",
      env ? { },
    }:
    pkgs.writeShellApplication {
      inherit name;
      runtimeInputs = [
        pkgs.coreutils
        package
      ];
      text =
        let
          envFlags = lib.concatStringsSep " " (lib.mapAttrsToList (k: v: "--setenv=${k}=${v}") env);
        in
        ''
          file="$1"

          cleanup() {
            echo "${name}: Done, cleaning up and exiting"
            rm -f "$file"
          }
          trap cleanup EXIT

          echo "${name}: Opening file $file using ${package.name}"
          systemd-run --unit=${name} --wait --service-type=${serviceType} --user ${envFlags} -- ${execCmd} "$file"
        '';
    };

  xdgOpenPdf = mkXdgFileOpener {
    name = "xdg-open-pdf";
    inherit (cfg.pdf) package;
    serviceType = "forking";
    env.RUST_LOG = "error";
  };

  xdgOpenVideo = mkXdgFileOpener {
    name = "xdg-open-video";
    inherit (cfg.video) package;
    serviceType = "forking";
    env.RUST_LOG = "error";
  };

  xdgOpenImage = mkXdgFileOpener {
    name = "xdg-open-image";
    inherit (cfg.image) package;
    env.RUST_LOG = "error";
  };

  xdgOpenUrl = pkgs.writeShellApplication {
    name = "xdgopenurl";
    runtimeInputs = [ pkgs.coreutils ];
    text = ''
      url="$1"

      if [[ -z "$url" ]]; then
        echo "No URL provided - xdg handlers"
        exit 1
      fi

      echo "XDG open url: $url"

      # Function to check if a binary exists in the givc app prefix
      search_bin() {
        [ -x "${config.ghaf.givc.appPrefix}/$1" ]
      }

      start_browser() {
       "${config.ghaf.givc.appPrefix}/$1" --disable-gpu --enable-features=UseOzonePlatform --ozone-platform=wayland "$url"
      }

      # Try to detect available browsers
      if search_bin google-chrome-stable; then
        echo "Google Chrome detected, opening URL locally."
        start_browser google-chrome-stable
      elif search_bin chromium; then
        echo "Chromium detected, opening URL locally."
        start_browser chromium
      else
        echo "No supported browser found on the system"
      fi

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
      ${config.ghaf.givc.appPrefix}/element-desktop --enable-logging --disable-gpu --enable-features=UseOzonePlatform --ozone-platform=wayland "$url"
    '';
  };

in
{
  _file = ./xdghandlers.nix;

  options.ghaf.xdghandlers = {
    pdf = {
      enable = lib.mkEnableOption "XDG PDF Handler";
      package = lib.mkPackageOption pkgs "cosmic-reader" { } // {
        readOnly = true;
      };
    };
    image = {
      enable = lib.mkEnableOption "XDG Image Handler";
      package = lib.mkPackageOption pkgs "oculante" { } // {
        readOnly = true;
      };
    };
    video = {
      enable = lib.mkEnableOption "XDG Video Handler";
      package = lib.mkPackageOption pkgs "cosmic-player" { } // {
        readOnly = true;
      };
    };
    url.enable = lib.mkEnableOption "XDG URL Handler";
    elementDesktop.enable = lib.mkEnableOption "XDG Element Desktop Handler";
  };

  config = lib.mkIf config.ghaf.givc.enable {
    environment.systemPackages =
      (lib.optional cfg.pdf.enable cfg.pdf.package)
      ++ (lib.optional cfg.image.enable cfg.image.package)
      ++ (lib.optional cfg.video.enable cfg.video.package);

    ghaf.givc.appvm.applications =
      (lib.optional cfg.pdf.enable {
        name = "xdg-pdf";
        command = lib.getExe xdgOpenPdf;
        args = [ "file" ];
        directories = [ "/run/xdg/pdf" ];
      })
      ++ (lib.optional cfg.image.enable {
        name = "xdg-image";
        command = lib.getExe xdgOpenImage;
        args = [ "file" ];
        directories = [ "/run/xdg/image" ];
      })
      ++ (lib.optional cfg.video.enable {
        name = "xdg-video";
        command = lib.getExe xdgOpenVideo;
        args = [ "file" ];
        directories = [ "/run/xdg/video" ];
      })
      ++ (lib.optional cfg.url.enable {
        name = "xdg-url";
        command = lib.getExe xdgOpenUrl;
        args = [ "url" ];
      })
      ++ (lib.optional cfg.elementDesktop.enable {
        name = "xdg-element-desktop";
        command = lib.getExe xdgOpenElement;
        args = [ "url" ];
      });

    # Set up MicroVM shares for each MIME type and mount them to /run/xdg
    # These shares are also passed to the AppVMs where XDG items are enabled
    microvm.shares =
      (lib.optional cfg.pdf.enable {
        tag = "xdgshare-pdf";
        proto = "virtiofs";
        securityModel = "passthrough";
        source = "${xdgHostRoot}/pdf";
        mountPoint = "/run/xdg/pdf";
      })
      ++ (lib.optional cfg.image.enable {
        tag = "xdgshare-image";
        proto = "virtiofs";
        securityModel = "passthrough";
        source = "${xdgHostRoot}/image";
        mountPoint = "/run/xdg/image";
      })
      ++ (lib.optional cfg.video.enable {
        tag = "xdgshare-video";
        proto = "virtiofs";
        securityModel = "passthrough";
        source = "${xdgHostRoot}/video";
        mountPoint = "/run/xdg/video";
      });

    fileSystems =
      (lib.optionalAttrs cfg.pdf.enable {
        "/run/xdg/pdf".options = [
          "rw"
          "nodev"
          "nosuid"
          "noexec"
        ];
      })
      // (lib.optionalAttrs cfg.image.enable {
        "/run/xdg/image".options = [
          "rw"
          "nodev"
          "nosuid"
          "noexec"
        ];
      })
      // (lib.optionalAttrs cfg.video.enable {
        "/run/xdg/video".options = [
          "rw"
          "nodev"
          "nosuid"
          "noexec"
        ];
      });
  };
}
