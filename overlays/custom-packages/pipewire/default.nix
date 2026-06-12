# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
# Fast-forward to 1.6.6 before it's available in nixpkgs
# Fixes audio crackling issue
{ prev }:
prev.pipewire.overrideAttrs {
  version = "1.6.6";
  src = prev.fetchFromGitLab {
    domain = "gitlab.freedesktop.org";
    owner = "pipewire";
    repo = "pipewire";
    tag = "1.6.6";
    hash = "sha256-pyZozhJomFT4QkJv/NKkXpbknmVxjv8hCxZV6RcIHmE=";
  };
}
