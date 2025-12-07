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
    google-chromecast = mkOption {
      description = "Google Chromecast service configuration";
      type = types.submodule {
        options = {
          enable = mkEnableOption "Chromecast service";

          vmName = mkOption {
            type = types.str;
            example = "chrome-vm";
            description = "The name of the chromium/chrome VM to setup chromecast for.";
            default = "chrome-vm";
          };
        };
      };
      default = {
        enable = false;
        vmName = "chrome-vm";
      };
    };
    alpaca-ollama = mkEnableOption "Alpaca/ollama service";
    wireguard-gui = mkEnableOption "Wireguard GUI service";
  };
  config = mkIf cfg.enable {
    ghaf.reference.services = {
      dendrite-pinecone.enable = mkForce (cfg.dendrite && isNetVM);
      proxy-server.enable = mkForce (cfg.proxy-business && isNetVM);
      chromecast = mkIf (cfg.google-chromecast.enable && isNetVM) {
        enable = mkForce true;
        vmName = mkForce cfg.google-chromecast.vmName;
      };
      ollama.enable = mkForce (cfg.alpaca-ollama && isGuiVM);
      wireguard-gui-config.enable = mkForce cfg.wireguard-gui;
    };
    assertions = [
      {
        assertion = cfg.chromecast.vmName != null;
        message = "Either chrome or chromium VM must be enabled (vmName cannot be null) for chromecast feature.";
      }
    ];
  };
}
