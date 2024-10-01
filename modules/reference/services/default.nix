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
  ];
  options.ghaf.reference.services = {
    enable = mkEnableOption "Enable the Ghaf reference services";
    dendrite = mkEnableOption "Enable the dendrite-pinecone service";
    proxy-business = mkEnableOption "Enable the proxy server service";
  };
  config = mkIf cfg.enable {
    ghaf.reference.services = {
      dendrite-pinecone.enable = mkForce (cfg.dendrite && isNetVM);
      proxy-server.enable = mkForce (cfg.proxy-business && isNetVM);
    };
  };
}
