# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
{ config, lib, ... }:
let
  cfg = config.ghaf.profiles.release;
  inherit (lib) mkEnableOption mkIf;
in
{
  _file = ./release.nix;

  options.ghaf.profiles.release = {
    enable = (mkEnableOption "release profile") // {
      default = false;
    };
  };

  config = mkIf cfg.enable {
    # Enable minimal profile as base
    ghaf.profiles.minimal.enable = true;

    # Enable default accounts and passwords
    # TODO this needs to be refined when we define a policy for the
    # processes and the UID/groups that should be enabled by default
    # if not already covered by systemd
    # ghaf.users.admin.enable = true;
    ghaf = {
      # No Nix on a release device.
      #
      # `ghaf.nix.enable` drives NixOS' `nix.enable` (modules/common/nix.nix), so
      # turning it off drops the daemon, takes nix out of systemPackages. That is a
      # ~160 MB closure the image cannot use: release updates go through verity
      # A/B sysupdate, not nixos-rebuild, and on verity the store is read-only.
      #
      # The settings it also carried (`keep-outputs`, `keep-derivations`) only
      # make sense on a machine that builds; a release device never does.
      nix.enable = lib.mkDefault false;
    };

    # Keep the nixpkgs *source* out of release images.
    nixpkgs.flake.setNixPath = lib.mkDefault false;
    nixpkgs.flake.setFlakeRegistry = lib.mkDefault false;
  };
}
