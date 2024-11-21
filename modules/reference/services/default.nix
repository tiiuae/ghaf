# Copyright 2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{ config, lib, ... }:
let
  inherit (lib) mkEnableOption mkIf mkForce;
  cfg = config.ghaf.reference.services;
  isNetVM = "net-vm" == config.system.name;
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

  ];
  options.ghaf.reference.services = {
    enable = mkEnableOption "Ghaf reference services";
    dendrite = mkEnableOption "dendrite-pinecone service";
    proxy-business = mkEnableOption "Enable the proxy server service";
    google-chromecast = mkEnableOption "Chromecast service";
    ollama = mkEnableOption "ollama service";
  };
  config = mkIf cfg.enable {
    ghaf.reference.services = {
      dendrite-pinecone.enable = mkForce (cfg.dendrite && isNetVM);
      proxy-server.enable = mkForce (cfg.proxy-business && isNetVM);
      chromecast.enable = mkForce (cfg.google-chromecast && isNetVM);
    };
  };
}
