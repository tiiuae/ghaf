# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
# TODO: Remove when upstream patch is available in nixpkgs
# Upstream patch - https://github.com/systemd/systemd/pull/40412
# nixpkgs https://github.com/NixOS/nixpkgs/blob/master/pkgs/os-specific/linux/systemd/default.nix
{ prev }:
prev.systemd.overrideAttrs (oldAttrs: {
  patches = oldAttrs.patches ++ [
    ./0001-pam_systemd_home-Use-PAM_TEXT_INFO-for-token-prompts.patch
  ];
})
