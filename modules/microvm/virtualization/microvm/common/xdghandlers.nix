# Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  lib,
  config,
  pkgs,
  ...
}:
let
  cfg = config.ghaf.xdghandlers;
  xdgOpenPdf = pkgs.writeShellApplication {
    name = "xdgopenpdf";
    runtimeInputs = [
      pkgs.coreutils
    ];
    # TODO: fix the url hack once GIVC supports file path arguments
    text = ''
      #!${pkgs.runtimeShell}
      file="$1"
      if [[ "$file" == http://example.com?p=* ]]; then
        file="''${file:21}"
        file=$(echo -n "$file" | base64 --decode)
      fi
      echo "XDG open PDF: $file"
      ${config.ghaf.givc.appPrefix}/run-waypipe ${config.ghaf.givc.appPrefix}/zathura "$file"
      rm "$file"
    '';
  };
  xdgOpenImage = pkgs.writeShellApplication {
    name = "xdgopenimage";
    runtimeInputs = [
      pkgs.coreutils
    ];
    # TODO: fix the url hack once GIVC supports file path arguments
    text = ''
      #!${pkgs.runtimeShell}
      file="$1"
      if [[ "$file" == http://example.com?p=* ]]; then
        file="''${file:21}"
        file=$(echo -n "$file" | base64 --decode)
      fi
      echo "XDG open image: $file"
      ${config.ghaf.givc.appPrefix}/run-waypipe ${config.ghaf.givc.appPrefix}/pqiv -i "$file"
      rm "$file"
    '';
  };
in
{
  options.ghaf.xdghandlers = {
    enable = lib.mkEnableOption "XDG Handlers";
  };

  config = lib.mkIf (cfg.enable && config.ghaf.givc.enable) {

    environment.systemPackages = [
      pkgs.zathura
      pkgs.pqiv
    ];

    ghaf.givc.appvm.applications = [
      {
        name = "xdg-pdf";
        command = "${xdgOpenPdf}/bin/xdgopenpdf";
        args = [ "url" ];
      }
      {
        name = "xdg-image";
        command = "${xdgOpenImage}/bin/xdgopenimage";
        args = [ "url" ];
      }
    ];

    microvm.shares = [
      {
        tag = "xdgshare-pdf";
        proto = "virtiofs";
        securityModel = "passthrough";
        source = "/storagevm/shared/shares/xdg/pdf";
        mountPoint = "/run/xdg/pdf";
      }
      {
        tag = "xdgshare-image";
        proto = "virtiofs";
        securityModel = "passthrough";
        source = "/storagevm/shared/shares/xdg/image";
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
