# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{ config, lib, ... }:
let
  cfg = config.ghaf.development.cuda;
  inherit (lib) mkEnableOption mkIf;
in
{
  _file = ./cuda.nix;

  options.ghaf.development.cuda = {
    enable = mkEnableOption "CUDA Support";
  };

  config = mkIf cfg.enable {
    #Enabling CUDA on any supported system requires below settings.
    nixpkgs.config.allowUnfree = lib.mkForce true;
    nixpkgs.config.allowBroken = lib.mkForce false;
    nixpkgs.config.cudaSupport = lib.mkForce false; # true;

    # Enable Opengl
    # Opengl enable is renamed to hardware.graphics.enable
    # This is needed for CUDA so set it if it is already not set
    hardware.graphics.enable = lib.mkForce true;
  };
}
