# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{ prev }:
prev.cosmic-session.overrideAttrs (oldAttrs: {
  # TODO: drop once https://github.com/pop-os/cosmic-session/pull/233 is released (not in COSMIC 1.11).
  postPatch = ''
        substituteInPlace data/start-cosmic \
          --replace-fail "DCONF_PROFILE SSH_AUTH_SOCK" 'DCONF_PROFILE ''${SSH_AUTH_SOCK:+SSH_AUTH_SOCK}' \
          --replace-fail \
            'exec /usr/bin/dbus-run-session -- /usr/bin/cosmic-session' \
            '/usr/bin/dbus-run-session -- /usr/bin/cosmic-session & wait $! 2>/dev/null || true' \
          --replace-fail \
            'exec /usr/bin/cosmic-session' \
            '/usr/bin/cosmic-session & wait $! 2>/dev/null || true' \
          --replace-fail '# Run cosmic-session' 'trap "command -v systemctl >/dev/null && systemctl --user stop cosmic-session.target graphical-session.target ghaf-session.target 2>/dev/null || true; kill ''$! 2>/dev/null || true" EXIT TERM INT HUP

    # Run cosmic-session'
  ''
  + (oldAttrs.postPatch or "");
})
