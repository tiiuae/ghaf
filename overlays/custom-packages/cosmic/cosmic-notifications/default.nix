# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{ prev }:
prev.cosmic-notifications.overrideAttrs (oldAttrs: {
  # The panel can take over 1s to connect on boot, the daemon then drops
  # it for good, leaving the panel without notifications and without some applets.
  # TODO: drop once https://github.com/pop-os/cosmic-notifications/pull/181 is released and ghaf bumps cosmic.
  postPatch = (oldAttrs.postPatch or "") + ''
    substituteInPlace src/subscriptions/applet.rs \
      --replace-fail "Duration::from_secs(1)," "Duration::from_secs(10),"
  '';
})
