# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{ pkgs, ... }:
let
  config = pkgs.nixos [ ./test-configuration.nix ];
in
config.config.system.build.toplevel
