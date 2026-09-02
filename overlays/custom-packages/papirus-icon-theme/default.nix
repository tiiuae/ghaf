# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{ prev }:
(prev.papirus-icon-theme.override {
  color = "grey";
  # Fixes a cross-compilation issue: papirus-folders is a build-time tool and
  # must run on the build platform, not the target.
  inherit (prev.buildPackages) papirus-folders;
}).overrideAttrs
  (old: {
    # breeze-icons (KDE) is only pulled in as an icon fallback (Papirus's
    # index.theme sets Inherits=breeze/breeze-dark). Dropping it saves
    # ~880 MiB per closure it's part of; Papirus itself is comprehensive
    # enough that the fallback is rarely exercised.
    propagatedBuildInputs = builtins.filter (
      p: (p.pname or "") != "breeze-icons"
    ) old.propagatedBuildInputs;
  })
