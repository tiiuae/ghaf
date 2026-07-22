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

    # TODO(release-policy): turn this warning into an assertion once the
    # release credential policy and CI provisioning are agreed.
    warnings =
      lib.optional
        (
          config.ghaf.users.admin.enable
          && config.ghaf.users.admin.hashedPassword == null
          && config.ghaf.users.admin.initialHashedPassword == null
        )
        "Release image ships the well-known default admin password. Set ghaf.users.admin.hashedPassword (e.g. mkpasswd -m yescrypt) for production images.";

    # Enable default accounts and passwords
    # TODO this needs to be refined when we define a policy for the
    # processes and the UID/groups that should be enabled by default
    # if not already covered by systemd
    # ghaf.users.admin.enable = true;
    ghaf = {
      # TODO we should move the nix-setup out of the development namespace
      development = {
        nix-setup = {
          enable = true;
          # Keep nix functional in release but do not pin the full nixpkgs
          # source tree into the closure (registry/nixPath are a debug aid).
          nixpkgs = lib.mkForce null;
        };
      };

    };
  };
}
