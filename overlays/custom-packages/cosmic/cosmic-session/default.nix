# Copyright 2022-2025 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
# Change the cosmic-session DCONF_PROFILE var to cosmic-ghaf
# Ref: https://github.com/pop-os/cosmic-session/blob/master/Justfile
{ prev }:
prev.cosmic-session.overrideAttrs (oldAttrs: {
  justFlags = builtins.map (
    flag: if flag == "cosmic" then "cosmic-ghaf" else flag
  ) oldAttrs.justFlags;
})
