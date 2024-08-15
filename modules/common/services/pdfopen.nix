# Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  config,
  lib,
  pkgs,
  ...
}:
let
  inherit (builtins) toString;
  inherit (lib)
    mkEnableOption
    mkOption
    mkIf
    types
    ;
  cfg = config.ghaf.services.pdfopener;

  # TODO: Fix the path to get the sshKeyPath so that
  # openPdf can be exported as a normal package from
  # packaged/flake-module.nix and hence easily imported
  # into all targets
  openPdf = pkgs.callPackage ../../../packages/openPdf {
    inherit (config.ghaf.security.sshKeys) sshKeyPath;
  };
in
{
  options.ghaf.services.pdfopener = {
    enable = mkEnableOption "Enable the pdf opening service";
    xdgPdfPort = mkOption {
      type = types.int;
      default = 1200;
      description = "TCP port for the PDF XDG socket";
    };
  };

  config = mkIf cfg.enable {
    # PDF XDG handler service receives a PDF file path from the chromium-vm and executes the openpdf script
    systemd.user = {
      sockets."pdf" = {
        unitConfig = {
          Description = "PDF socket";
        };
        socketConfig = {
          ListenStream = "${toString cfg.xdgPdfPort}";
          Accept = "yes";
        };
        wantedBy = [ "sockets.target" ];
      };

      services."pdf@" = {
        description = "PDF opener";
        serviceConfig = {
          ExecStart = "${openPdf}/bin/openPdf";
          StandardInput = "socket";
          StandardOutput = "journal";
          StandardError = "journal";
        };
      };
    };

    # Open TCP port for the PDF XDG socket.
    networking.firewall.allowedTCPPorts = [ cfg.xdgPdfPort ];
  };
}
