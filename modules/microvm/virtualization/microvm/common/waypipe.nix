# Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  vmIndex,
  vm,
  configHost,
  cid,
}:
{
  config,
  lib,
  pkgs,

  ...
}:
let
  cfg = config.ghaf.waypipe;
  waypipePort = configHost.ghaf.virtualization.microvm.appvm.waypipeBasePort + vmIndex;
  waypipeBorder = lib.optionalString (
    cfg.waypipeBorder && vm.borderColor != null
  ) "--border \"${vm.borderColor}\"";
  runWaypipe = pkgs.writeScriptBin "run-waypipe" ''
    #!${pkgs.runtimeShell} -e
    ${pkgs.waypipe}/bin/waypipe --vsock -s ${toString waypipePort} server "$@"
  '';
  vsockproxy = pkgs.callPackage ../../../../../packages/vsockproxy { };
  guivmCID = configHost.ghaf.virtualization.microvm.guivm.vsockCID;
in
{
  options.ghaf.waypipe = with lib; {
    enable = mkEnableOption "Waypipe support";

    proxyService = lib.mkOption {
      type = lib.types.attrs;
      description = "vsockproxy service configuration for the AppVM";
      readOnly = true;
      visible = false;
    };

    waypipeService = lib.mkOption {
      type = lib.types.attrs;
      description = "Waypipe service configuration for the AppVM";
      readOnly = true;
      visible = false;
    };

    waypipeBorder = lib.mkEnableOption "Waypipe window border";
  };

  config = lib.mkIf cfg.enable {

    environment.systemPackages = [
      pkgs.waypipe
      runWaypipe
    ];

    ghaf.waypipe = {
      # Waypipe service runs in the GUIVM and listens for incoming connections from AppVMs
      waypipeService = {
        enable = true;
        description = "Waypipe for ${vm.name}";
        serviceConfig = {
          Type = "simple";
          Restart = "always";
          RestartSec = "1";
          ExecStart = "${pkgs.waypipe}/bin/waypipe --vsock --secctx \"${vm.name}\" ${waypipeBorder} -s ${toString waypipePort} client";
        };
        startLimitIntervalSec = 0;
        partOf = [ "ghaf-session.target" ];
        wantedBy = [ "ghaf-session.target" ];
      };

      # vsockproxy is used on host to forward data between AppVMs and GUIVM
      proxyService = {
        enable = true;
        description = "vsockproxy for ${vm.name}";
        serviceConfig = {
          Type = "simple";
          Restart = "always";
          RestartSec = "1";
          ExecStart = "${vsockproxy}/bin/vsockproxy ${toString waypipePort} ${toString guivmCID} ${toString waypipePort} ${toString cid}";
        };
        startLimitIntervalSec = 0;
        wantedBy = [ "multi-user.target" ];
      };
    };
  };
}
