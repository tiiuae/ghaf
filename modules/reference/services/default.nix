# Copyright 2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{ config, lib, ... }:
let
  inherit (lib)
    mkEnableOption
    mkIf
    mkForce
    ;
  cfg = config.ghaf.reference.services;
  isNetVM = "net-vm" == config.system.name;
  isGuiVM = "gui-vm" == config.system.name;

  appVms = lib.attrByPath [ "ghaf" "virtualization" "microvm" "appvm" "vms" ] { } config;
  wireguardGuiEnabledVms = lib.lists.map (app: app.vmName) (
    lib.lists.filter
      (
        app:
        let
          services = lib.attrByPath [ "ghaf" "reference" "services" ] { } app;
          wgService = services."wireguard-gui" or null;
        in
        wgService != null && (wgService.enable or false)
      )
      (
        lib.lists.concatMap (vm: map (app: (app // { vmName = "${vm.name}-vm"; })) vm.extraModules) (
          lib.attrsets.mapAttrsToList (name: vm: { inherit name; } // vm) (
            lib.filterAttrs (_: vm: vm.enable) appVms
          )
        )
      )
  );
in
{
  imports = [
    ./dendrite-pinecone/dendrite-pinecone.nix
    ./dendrite-pinecone/dendrite-config.nix
    ./proxy-server/3proxy-config.nix
    ./smcroute/smcroute.nix
    ./ollama/ollama.nix
    ./chromecast/chromecast.nix
    ./chromecast/chromecast-config.nix
    ./nw-packet-forwarder/nw-packet-forwarder.nix
    ./wireguard-gui/wireguard-gui-config.nix
  ];
  options.ghaf.reference.services = {
    enable = mkEnableOption "Ghaf reference services";
    dendrite = mkEnableOption "dendrite-pinecone service";
    proxy-business = mkEnableOption "Enable the proxy server service";
    google-chromecast = mkEnableOption "Chromecast service";
    alpaca-ollama = mkEnableOption "Alpaca/ollama service";
    wireguard-gui = mkEnableOption "Wireguard GUI service";
  };
  config = mkIf cfg.enable {
    ghaf.reference.services = {
      dendrite-pinecone.enable = mkForce (cfg.dendrite && isNetVM);
      proxy-server.enable = mkForce (cfg.proxy-business && isNetVM);
      chromecast.enable = mkForce (cfg.google-chromecast && isNetVM);
      ollama.enable = mkForce (cfg.alpaca-ollama && isGuiVM);
      wireguard-gui-config = {
        vms = mkIf (wireguardGuiEnabledVms != [ ]) (mkForce wireguardGuiEnabledVms);
        enable = mkForce (cfg.wireguard-gui && isGuiVM);
      };
    };
  };
}
