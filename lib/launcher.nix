# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
_: {
  rmDesktopEntries =
    pkgs:
    map (
      pkg:
      pkg.overrideAttrs (
        old:
        let
          pInst = if (old ? postInstall) then old.postInstall else "";
        in
        {
          postInstall = pInst + "rm -rf \"$out/share/applications\"";
        }
      )
    ) pkgs;
}
