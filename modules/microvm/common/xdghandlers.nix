# Copyright 2022-2025 TII (SSRC) and the Ghaf contributors
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
    runtimeInputs = [
      pkgs.coreutils
    ];
    text = ''
      #!${pkgs.runtimeShell}
      file="$1"
      echo "XDG open PDF: $file"
      ${config.ghaf.givc.appPrefix}/run-waypipe ${config.ghaf.givc.appPrefix}/zathura "$file"
      rm "$file"
    '';
  };

  # A script for opening image files launched by GIVC from AppVMs
  xdgOpenImage = pkgs.writeShellApplication {
    name = "xdgopenimage";
    runtimeInputs = [
      pkgs.coreutils
    ];
    text = ''
      #!${pkgs.runtimeShell}
      file="$1"
      echo "XDG open image: $file"
      ${config.ghaf.givc.appPrefix}/run-waypipe ${config.ghaf.givc.appPrefix}/oculante "$file"
      rm "$file"
    '';
  };
in
{
  options.ghaf.xdghandlers = {
    enable = lib.mkEnableOption "XDG Handlers";
  };

  config = lib.mkIf (cfg.enable && config.ghaf.givc.enable) {

    environment.systemPackages = with pkgs; [
      zathura
      oculante
    ];

    # Set up GIVC applications for XDG scripts
    ghaf.givc.appvm.applications = [
      {
        name = "xdg-pdf";
        command = "${xdgOpenPdf}/bin/xdgopenpdf";
        args = [ "file" ];
        directories = [ "/run/xdg/pdf" ];
      }
      {
        name = "xdg-image";
        command = "${xdgOpenImage}/bin/xdgopenimage";
        args = [ "file" ];
        directories = [ "/run/xdg/image" ];
      }
    ];

    # Set up MicroVM shares for each MIME type and mount them to /run/xdg
    # These shares are also passed to the AppVMs where XDG items are enabled
    microvm.shares = [
      {
        tag = "xdgshare-pdf";
        proto = "virtiofs";
        securityModel = "passthrough";
        source = "${xdgHostRoot}/pdf";
        mountPoint = "/run/xdg/pdf";
      }
      {
        tag = "xdgshare-image";
        proto = "virtiofs";
        securityModel = "passthrough";
        source = "${xdgHostRoot}/image";
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
