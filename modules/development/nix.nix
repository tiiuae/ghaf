# Copyright 2022-2023 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{...}: {
  nix.settings.experimental-features = ["nix-command" "flakes"];
  nix.extraOptions = ''
    keep-outputs          = true
    keep-derivations      = true
  '';
}
