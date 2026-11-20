# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{ config, lib, ... }:
let
  inherit (lib)
    mkEnableOption
    mkOption
    types
    mkIf
    mkForce
    ;
  cfg = config.ghaf.reference.services;
  isNetVM = "net-vm" == config.system.name;
  isGuiVM = "gui-vm" == config.system.name;
in
{
  _file = ./default.nix;

  imports = [
    ./dendrite-pinecone/dendrite-pinecone.nix
    ./dendrite-pinecone/dendrite-config.nix
    ./proxy/server.nix
    ./smcroute/smcroute.nix
    ./ollama/ollama.nix
    ./chromecast/chromecast.nix
    ./nw-packet-forwarder/nw-packet-forwarder.nix
    ./wireguard-gui/wireguard-gui-config.nix
  ];
  options.ghaf.reference.services = {
    enable = mkEnableOption "Ghaf reference services";
    dendrite = mkEnableOption "the dendrite-pinecone service";
    proxy = {
      enable = mkEnableOption "the proxy server service";
      server = mkOption {
        type = types.str;
        default = "net-vm";
        description = "The VM that runs the proxy server.";
      };
      clients = mkOption {
        type = types.listOf types.str;
        # Collected on the host and forwarded to the server VM, which cannot see the other VMs.
        default = lib.attrNames (
          lib.filterAttrs (
            _: vm: (lib.ghaf.vm.getConfig vm).ghaf.reference.services.proxy-client.enable or false
          ) (config.microvm.vms or { })
        );
        defaultText = lib.literalExpression "VMs that set ghaf.reference.services.proxy-client.enable";
        description = "VMs that reach the internet through the proxy server.";
      };
    };
    alpaca-ollama = mkEnableOption "Alpaca/ollama service";
    wireguard-gui = mkEnableOption "Wireguard GUI service";
  };
  config = mkIf cfg.enable {
    ghaf.reference.services = {
      dendrite-pinecone.enable = mkForce (cfg.dendrite && isNetVM);
      proxy-server = {
        enable = mkForce (cfg.proxy.enable && config.system.name == cfg.proxy.server);
        inherit (cfg.proxy) clients;
      };
      ollama.enable = mkForce (cfg.alpaca-ollama && isGuiVM);
      wireguard-gui-config.enable = mkForce cfg.wireguard-gui;
    };
  };
}
