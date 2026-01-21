# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{ prev }:
prev.systemd.overrideAttrs (oldAttrs: {
  patches = oldAttrs.patches ++ [
    ./0001-pam_systemd_home-Use-PAM_TEXT_INFO-for-token-prompts.patch
  ];
})
