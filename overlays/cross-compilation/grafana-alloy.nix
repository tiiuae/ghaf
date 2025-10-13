# Copyright 2022-2025 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# Fix grafana-alloy cross-compilation by disabling shell completion generation
# when building for a different platform.
_final: prev: {
  grafana-alloy = prev.grafana-alloy.overrideAttrs (old: {
    postInstall =
      prev.lib.optionalString (prev.stdenv.buildPlatform.canExecute prev.stdenv.hostPlatform)
        (old.postInstall or "");
  });
}
