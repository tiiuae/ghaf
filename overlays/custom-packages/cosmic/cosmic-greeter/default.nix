# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{ prev }:
prev.cosmic-greeter.overrideAttrs (oldAttrs: {
  patches = oldAttrs.patches ++ [
    ./0001-Replace-fallback-background-with-Ghaf-default.patch
    ./0001-Fix-softlock.patch
    ./0002-fix-username-handle-empty-usernames.patch
    ./0003-greeter-avoid-auth-on-empty-password.patch
  ];
})
