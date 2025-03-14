# Copyright 2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.ghaf.reference.appvms;
in
{
  imports = [ ];

  options.ghaf.reference.appvms = {
    enable = lib.mkEnableOption "Enable the Ghaf reference appvms module";
    chromium-vm = lib.mkEnableOption "Enable the Chromium appvm";
    chrome-vm = lib.mkEnableOption "Enable the Google Chrome appvm";
    gala-vm = lib.mkEnableOption "Enable the Gala appvm";
    zathura-vm = lib.mkEnableOption "Enable the Zathura appvm";
    comms-vm = lib.mkEnableOption ''
      Enable the communications appvm
        - Element
        - Slack
        - Zoom
    '';
    business-vm = lib.mkEnableOption "Enable the Business appvm";
    enabled-app-vms = lib.mkOption {
      type = lib.types.listOf lib.types.attrs;
      default = [ ];
      description = ''
        List of appvms to include in the Ghaf reference appvms module
      '';
    };
    shm-audio-enabled-vms = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = ''
        List of appvms that use shared memory to handle audio data
      '';
    };
    shm-gui-enabled-vms = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = ''
        List of appvms that use shared memory to handle GUI data
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    ghaf.reference.appvms = {
      enabled-app-vms =
        (lib.optionals cfg.chromium-vm [ (import ./chromium.nix { inherit pkgs lib config; }) ])
        ++ (lib.optionals cfg.chrome-vm [ (import ./google-chrome.nix { inherit pkgs lib config; }) ])
        ++ (lib.optionals cfg.gala-vm [ (import ./gala.nix { inherit pkgs lib config; }) ])
        ++ (lib.optionals cfg.zathura-vm [ (import ./zathura.nix { inherit pkgs lib config; }) ])
        ++ (lib.optionals cfg.comms-vm [ (import ./comms.nix { inherit pkgs lib config; }) ])
        ++ (lib.optionals cfg.business-vm [ (import ./business.nix { inherit pkgs lib config; }) ]);
    };
  };
}
