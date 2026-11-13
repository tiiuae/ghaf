# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{ lib }:
{
  # Remove desktop entries from a single package
  # Handles both postInstall and buildCommand build styles
  rmDesktopEntry =
    pkg:
    pkg.overrideAttrs (
      old:
      let
        pInst = if (old ? postInstall) then old.postInstall else "";
      in
      {
        postInstall = pInst + "rm -rf \"$out/share/applications\"";
      }
      // lib.optionalAttrs (old ? buildCommand) {
        buildCommand = old.buildCommand + "rm -rf \"$out/share/applications\"";
      }
    );

  # Remove desktop entries from a list of packages
  # A wrapper rather than an override, so the package itself stays shared and cached
  rmDesktopEntries =
    pkgs:
    map (
      pkg:
      pkgs.symlinkJoin {
        inherit (pkg) name;
        meta = removeAttrs (pkg.meta or { }) [ "outputsToInstall" ];
        paths = [ pkg ];
        postBuild = "rm -rf \"$out/share/applications\"";
      }
    );
}
