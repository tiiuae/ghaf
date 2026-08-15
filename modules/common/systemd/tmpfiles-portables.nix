# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# Carries NixOS PR #553061 -- "nixos/systemd/tmpfiles: only link portables.conf
# when portabled is built" -- until it reaches the nixpkgs we pin.
#
# NOT an overlay, and it cannot be one: the dangling link is produced by a NixOS
# module rather than by a package. The module symlink-joins
# systemd.tmpfiles.packages into environment.etc."tmpfiles.d" and builds the
# offending entry with an inline `pkgs.runCommand`, so there is no package
# attribute for an overlay to override -- and patching systemd itself to ship an
# empty example file would rebuild the world to delete one symlink.
#
# Delete this file once PR #553061 is in the pinned nixpkgs; the upstream fix
# omits the link entirely, which is tidier than shipping an empty conf.
{
  config,
  lib,
  ...
}:
{
  _file = ./tmpfiles-portables.nix;

  # `or true` so an unexpected systemd package that does not carry the flag in
  # passthru leaves upstream behaviour alone rather than masking a real file.
  config = lib.mkIf (!(config.systemd.package.withPortabled or true)) {
    environment.etc."tmpfiles.d/portables.conf".text = ''
      # Intentionally empty. systemd here is built without portabled, so
      # upstream's portables.conf does not exist and NixOS would otherwise link
      # /etc/tmpfiles.d/portables.conf to a path that is not there.
      # See NixOS PR #553061; remove this file when that lands.
    '';
  };
}
