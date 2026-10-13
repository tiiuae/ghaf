# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{ prev }:
prev.cosmic-session.overrideAttrs (oldAttrs: {
  # TODO: drop once https://github.com/pop-os/cosmic-session/pull/233 is released (COSMIC 1.11).
  postPatch = (oldAttrs.postPatch or "") + ''
    substituteInPlace data/start-cosmic \
      --replace-fail "DCONF_PROFILE SSH_AUTH_SOCK" 'DCONF_PROFILE ''${SSH_AUTH_SOCK:+SSH_AUTH_SOCK}'
  '';
})
