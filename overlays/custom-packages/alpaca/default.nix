# Copyright 2022-2025 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
# 5.3.0 introduced a breaking change, preventing the app from starting
# 6.0.0+ promises to fix the issue, but not yet available as of April 14 2025
# Refs:
# https://github.com/Jeffser/Alpaca/issues/626
{ prev }:
prev.alpaca.overrideAttrs (_oldAttrs: {
  version = "5.2.0";

  src = prev.fetchFromGitHub {
    owner = "Jeffser";
    repo = "Alpaca";
    tag = "5.2.0";
    hash = "sha256-uUGsdHrqzA5fZ4LNtX04H4ue9n4JQrkTYW2PCCFYFHc=";
  };
})
