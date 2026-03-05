# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  config,
  lib,
  hostConfig ? { },
  ...
}:
let
  cfg = config.ghaf.reference.services.wireguard-gui-config;
  inherit (lib)
    mkIf
    hasAttrByPath
    mkForce
    mkDefault
    lists
    attrByPath
    attrsets
    mkEnableOption
    ;
  isHost = hasAttrByPath [
    "hardware"
    "devices"
  ] config.ghaf;
  inheritedVmConfig = attrByPath [ "reference" "services" "wireguard-gui-vmconfig" ] { } hostConfig;
  appVms = lib.attrByPath [ "ghaf" "virtualization" "microvm" "appvm" "enabledVms" ] { } config;
  # Extract all VMs where wireguard-gui is enabled
  # Look through applications and their extraModules (new composition model)
  # Flatten: for each VM -> for each application -> for each extraModule
  wireguardEnabledVms =
    lists.filter
      (
        app:
        let
          services = attrByPath [ "ghaf" "reference" "services" ] { } app;
          wgService = services."wireguard-gui" or null;
        in
        wgService != null && (wgService.enable or false)
      )
      (
        lists.concatMap (
          vm:
          let
            vmDef = attrByPath [ "evaluatedConfig" "config" "ghaf" "appvm" "vmDef" ] { } vm;
            vmApplications = vmDef.applications or [ ];
            vmExtraModules = vmDef.extraModules or [ ];
            appExtraModules = lists.concatMap (
              appDef: map (extraMod: extraMod // { vmName = "${vm.name}-vm"; }) (appDef.extraModules or [ ])
            ) vmApplications;
            topLevelExtraModules = map (extraMod: extraMod // { vmName = "${vm.name}-vm"; }) vmExtraModules;
          in
          appExtraModules ++ topLevelExtraModules
        ) (attrsets.mapAttrsToList (_name: vm: vm) appVms)
      );

  # Map only the vmName values
  wgEnabledVmNames = lists.map (app: app.vmName) wireguardEnabledVms;
  # Server ports per VM
  wgServerPortsByVm =
    lists.map
      (app: {
        inherit (app) vmName;
        inherit (app.ghaf.reference.services."wireguard-gui") serverPorts;
      })
      (
        lists.filter (
          app: (app.ghaf.reference.services."wireguard-gui".serverPorts or [ ]) != [ ]
        ) wireguardEnabledVms
      );

in
{
  _file = ./wireguard-gui-config.nix;

  options.ghaf.reference.services.wireguard-gui-config = {
    enable = mkEnableOption "wireguard gui config";
  };
  imports = [
    ./wireguard-gui-vmconfig.nix
  ];
  config = mkIf cfg.enable {

    ghaf.reference.services.wireguard-gui-vmconfig = lib.mkMerge [
      (mkIf isHost {
        netVmExternalNic = mkForce (lib.head config.ghaf.hardware.definition.network.pciDevices).name;
        enabledVmNames = mkIf (wgEnabledVmNames != [ ]) (mkForce wgEnabledVmNames);
        serverPortsByVm = mkIf (wgServerPortsByVm != [ ]) (mkForce wgServerPortsByVm);
      })
      (mkIf (!isHost) {
        netVmExternalNic = mkIf ((inheritedVmConfig.netVmExternalNic or "") != "") (
          mkDefault inheritedVmConfig.netVmExternalNic
        );
        enabledVmNames = mkIf ((inheritedVmConfig.enabledVmNames or [ ]) != [ ]) (
          mkDefault inheritedVmConfig.enabledVmNames
        );
        serverPortsByVm = mkIf ((inheritedVmConfig.serverPortsByVm or [ ]) != [ ]) (
          mkDefault inheritedVmConfig.serverPortsByVm
        );
      })
    ];
  };
}
