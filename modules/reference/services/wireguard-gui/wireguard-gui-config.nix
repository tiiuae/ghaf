# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  config,
  lib,
  ...
}:
let
  cfg = config.ghaf.reference.services.wireguard-gui-config;
  inherit (lib)
    mkIf
    hasAttrByPath
    mkForce
    lists
    attrByPath
    attrsets
    filterAttrs
    mkEnableOption
    ;
  isHost = hasAttrByPath [
    "hardware"
    "devices"
  ] config.ghaf;
  appVms = lib.attrByPath [ "ghaf" "virtualization" "microvm" "appvm" "vms" ] { } config;
  # Extract all VMs where wireguard-gui is enabled
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
        lists.concatMap (vm: map (app: (app // { vmName = "${vm.name}-vm"; })) vm.extraModules) (
          attrsets.mapAttrsToList (name: vm: { inherit name; } // vm) (filterAttrs (_: vm: vm.enable) appVms)
        )
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
  options.ghaf.reference.services.wireguard-gui-config = {
    enable = mkEnableOption "wireguard gui config";
  };
  imports = [
    ./wireguard-gui-vmconfig.nix
  ];
  config = mkIf cfg.enable {

    ghaf.reference.services.wireguard-gui-vmconfig = {
      netVmExternalNic = mkIf isHost (
        mkForce (lib.head config.ghaf.hardware.definition.network.pciDevices).name
      );

      enabledVmNames = mkIf (wgEnabledVmNames != [ ]) (mkForce wgEnabledVmNames);

      serverPortsByVm = mkIf (wgServerPortsByVm != [ ]) (mkForce wgServerPortsByVm);
    };
  };
}
