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
  options.ghaf.reference.appvms.enable = lib.mkEnableOption "Enable the Ghaf reference appvms module";

  config = lib.mkIf cfg.enable {
    ghaf.virtualization.microvm.appvm.vms = lib.foldl (a: b: a // b) { } [
      (import ./chromium.nix { inherit pkgs lib config; })
      (import ./google-chrome.nix { inherit pkgs lib config; })
      (import ./gala.nix { inherit pkgs lib config; })
      (import ./zathura.nix { inherit pkgs lib config; })
      (import ./comms.nix { inherit pkgs lib config; })
      (import ./business.nix { inherit pkgs lib config; })
    ];
  };
}
