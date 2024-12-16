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
  cfg = config.ghaf.services.xdgopener;

  # TODO: Fix the path to get the sshKeyPath so that
  # ghaf-xdg-open can be exported as a normal package from
  # packaged/flake-module.nix and hence easily imported
  # into all targets
  ghaf-xdg-open = pkgs.callPackage ../../../packages/ghaf-xdg-open {
    inherit (config.ghaf.security.sshKeys) sshKeyPath;
    user = config.ghaf.users.appUser.name;
  };
in
{
  options.ghaf.services.xdgopener = {
    enable = mkEnableOption "Enable the XDG opening service";
    xdgPort = mkOption {
      type = types.int;
      default = 1200;
      description = "TCP port for the XDG socket";
    };
  };

  config = mkIf cfg.enable {
    # XDG handler service receives a file path and type over TCP connection and executes ghaf-xdg-open script
    systemd = {
      sockets."xdg" = {
        unitConfig = {
          Description = "Ghaf XDG socket";
        };
        socketConfig = {
          ListenStream = "${toString cfg.xdgPort}";
          Accept = "yes";
        };
        wantedBy = [ "sockets.target" ];
      };

      services."xdg@" = {
        description = "XDG opener";
        serviceConfig = {
          ExecStart = "${ghaf-xdg-open}/bin/ghaf-xdg-open";
          StandardInput = "socket";
          StandardOutput = "journal";
          StandardError = "journal";
        };
      };
    };

    # Open TCP port for the XDG socket
    networking.firewall.allowedTCPPorts = [ cfg.xdgPort ];
  };
}
