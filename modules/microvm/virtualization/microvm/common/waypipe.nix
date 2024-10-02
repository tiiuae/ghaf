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
  cfgShm = configHost.ghaf.shm.service;
  waypipePort = configHost.ghaf.virtualization.microvm.appvm.waypipeBasePort + vmIndex;
  waypipeBorder = lib.optionalString (
    cfg.waypipeBorder && vm.borderColor != null
  ) "--border \"${vm.borderColor}\"";
  displayOptServer =
    if cfgShm.gui.enabled then
      "-s " + cfgShm.gui.serverSocketPath "gui" "-${vm.name}-vm"
    else
      "--vsock -s ${toString waypipePort}";
  displayOptClient =
    if cfgShm.gui.enabled && (lib.lists.elem "${vm.name}-vm" cfgShm.gui.clients) then
      "-s " + cfgShm.gui.clientSocketPath
    else
      "--vsock -s ${toString waypipePort}";
  runWaypipe =
    let
      script = ''
        #!${pkgs.runtimeShell} -e
        ${pkgs.waypipe}/bin/waypipe ${displayOptClient} server "$@"
      '';
    in
    pkgs.writeScriptBin "run-waypipe" script;
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

    # Ensure that the vulkan drivers are available for the waypipe to utilize
    # it is already available in the GUIVM so this will ensure it is there in the appvms that enable the waypipe only.
    hardware.graphics.enable = true;

    ghaf.waypipe = {
      # Waypipe service runs in the GUIVM and listens for incoming connections from AppVMs
      waypipeService = {
        enable = true;
        description = "Waypipe for ${vm.name}";
        serviceConfig = {
          Type = "simple";
          Restart = "always";
          RestartSec = "1";
          ExecStart = "${pkgs.waypipe}/bin/waypipe --secctx \"${vm.name}\" ${waypipeBorder} ${displayOptServer} client";
          # Waypipe does not handle the SIGTERM signal properly, which is the default signal sent
          # by systemd when stopping a service
          KillSignal = "SIGINT";
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
